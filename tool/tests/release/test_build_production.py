from __future__ import annotations

import base64
from contextlib import redirect_stderr, redirect_stdout
import io
import json
import os
from pathlib import Path
import plistlib
import tempfile
import unittest
import zipfile
from unittest.mock import patch, MagicMock
from types import SimpleNamespace

from tool.release import build_production as release


class ProductionBuildTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.defines_file = self.root / "production.json"
        self.key = base64.urlsafe_b64encode(bytes(range(32))).decode().rstrip("=")
        self.values = {
            "MIUCAM_PURCHASE_VERIFIER_URL": "https://billing.miucam.app/verify",
            "MIUCAM_LICENSE_PUBLIC_KEY": self.key,
        }
        self.write_defines()

    def write_defines(self):
        self.defines_file.write_text(json.dumps(self.values))

    def test_accepts_production_defines_and_normalizes_boolean_values(self):
        self.values["MIUCAM_BROADCAST_PAYWALL_ENABLED"] = True
        self.write_defines()
        self.assertEqual(release.load_defines(self.defines_file)[
            "MIUCAM_BROADCAST_PAYWALL_ENABLED"], "true")

    def test_rejects_missing_and_malformed_defines_without_echoing_contents(self):
        for text in ('{"secret":"receipt_private"', "[]", '{"secret": 123}'):
            with self.subTest(text=text):
                self.defines_file.write_text(text)
                with self.assertRaises(release.ReleaseError) as error:
                    release.load_defines(self.defines_file)
                self.assertNotIn("receipt_private", str(error.exception))
        self.defines_file.unlink()
        with self.assertRaises(release.ReleaseError):
            release.load_defines(self.defines_file)

    def test_rejects_development_and_placeholder_endpoints(self):
        for url in ("", "http://billing.miucam.app/verify", "https://localhost/verify",
                    "https://127.0.0.1/verify", "https://192.168.0.2/verify",
                    "https://billing.example.com/verify", "https://YOUR-BACKEND/verify",
                    "https://billing.test/verify", "https://billing.miucam.app/health",
                    "https://user:secret@billing.miucam.app/verify",
                    "https://@billing.miucam.app/verify", "https://miucam.app:bad/verify",
                    "https://billing.miucam.app/verify?secret=data",
                    "https://billing.miucam.app/verify#key"):
            with self.subTest(url=url):
                self.values["MIUCAM_PURCHASE_VERIFIER_URL"] = url
                self.write_defines()
                with self.assertRaises(release.ReleaseError):
                    release.load_defines(self.defines_file)

    def test_rejects_missing_noncanonical_and_wrong_length_public_keys(self):
        for key in ("", "YOUR_BASE64URL_PUBLIC_KEY", "a" * 42, "A" * 43,
                    self.key[:-1] + "_", self.key + "==", "receipt_private"):
            with self.subTest(key=key):
                self.values["MIUCAM_LICENSE_PUBLIC_KEY"] = key
                self.write_defines()
                with self.assertRaises(release.ReleaseError):
                    release.load_defines(self.defines_file)

    def test_rejects_trial_bypass_pilot_and_unknown_overrides(self):
        for key, value in (("MIUCAM_BROADCAST_PAYWALL_ENABLED", False),
                           ("MIUCAM_WEBRTC_PILOT", True),
                           ("REPORT_SCENE", "store"),
                           ("MIUCAM_TEST_ENDPOINTS_ENABLED", "true")):
            with self.subTest(key=key):
                values = {**self.values, key: value}
                self.defines_file.write_text(json.dumps(values))
                with self.assertRaises(release.ReleaseError):
                    release.load_defines(self.defines_file)

    def signing_fixture(self, **overrides):
        android = self.root / "android"
        android.mkdir(exist_ok=True)
        (android / "upload.jks").write_bytes(b"test fixture; Gradle verifies real keys")
        values = dict(storeFile="upload.jks", storePassword="private_password",
                      keyAlias="miucam-upload", keyPassword="private_key_password")
        values.update(overrides)
        (android / "key.properties").write_text(
            "\n".join(f"{key}={value}" for key, value in values.items()))

    def test_requires_existing_android_upload_key(self):
        with self.assertRaises(release.ReleaseError):
            release.check_android_signing(self.root)
        self.signing_fixture()
        release.check_android_signing(self.root)
        (self.root / "android/upload.jks").unlink()
        with self.assertRaises(release.ReleaseError):
            release.check_android_signing(self.root)

    def test_rejects_debug_and_placeholder_signing_without_printing_passwords(self):
        for overrides in ({"keyAlias": "androiddebugkey"}, {"storePassword": "replace-me"},
                          {"keyPassword": ""}, {"storeFile": "does-not-exist"}):
            with self.subTest(overrides=overrides):
                self.signing_fixture(**overrides)
                with self.assertRaises(release.ReleaseError) as error:
                    release.check_android_signing(self.root)
                self.assertNotIn("private_password", str(error.exception))

    def test_rejects_empty_keystore_and_multiline_signing(self):
        self.signing_fixture()
        (self.root / "android/upload.jks").write_bytes(b"")
        with self.assertRaises(release.ReleaseError):
            release.check_android_signing(self.root)
        (self.root / "android/key.properties").write_text("storeFile=folder\\\nupload.jks")
        with self.assertRaises(release.ReleaseError):
            release.check_android_signing(self.root)

    def ios_fixture(self, **overrides):
        project = self.root / "ios/Runner.xcodeproj/project.pbxproj"
        project.parent.mkdir(parents=True, exist_ok=True)
        project.write_text("DEVELOPMENT_TEAM = ABCD123456;")
        options = self.root / "ExportOptions.plist"
        options.write_bytes(plistlib.dumps({"teamID": "ABCD123456",
                                           "method": "app-store-connect", **overrides}))
        return options

    def test_ios_requires_macos_and_explicit_app_store_export(self):
        options = self.ios_fixture()
        with patch.object(release.sys, "platform", "linux"):
            with self.assertRaises(release.ReleaseError):
                release.check_ios_signing(self.root, options)
        with patch.object(release.sys, "platform", "darwin"):
            with self.assertRaises(release.ReleaseError):
                release.check_ios_signing(self.root, None)
            release.check_ios_signing(self.root, options)

    def test_ios_rejects_mismatched_team_or_development_export(self):
        with patch.object(release.sys, "platform", "darwin"):
            for override in ({"teamID": "OTHER12345"}, {"method": "development"},
                             {"teamID": ""}, {"teamID": 123},
                             {"destination": "upload"}):
                with self.subTest(override=override):
                    with self.assertRaises(release.ReleaseError):
                        release.check_ios_signing(self.root, self.ios_fixture(**override))

    def backend_response(self, **overrides):
        return {"ready": True, "storeEnvironment": "production", "source": "google_play",
                "productId": release.PRODUCT_ID, "licensePublicKey": self.key, **overrides}

    def opener(self, body, *, status=200):
        opener = MagicMock()
        response = opener.open.return_value.__enter__.return_value
        response.status = status
        response.read.return_value = json.dumps(body).encode()
        return opener

    def test_backend_preflight_sends_no_receipt_and_checks_matching_platform(self):
        for platform, source in release.SOURCES.items():
            with self.subTest(platform=platform):
                opener = self.opener(self.backend_response(source=source))
                with patch.object(release, "build_opener", return_value=opener):
                    release.check_backend(self.values, platform)
                request = opener.open.call_args.args[0]
                self.assertEqual(json.loads(request.data), {"preflight": True,
                    "productId": release.PRODUCT_ID, "source": source})
                self.assertEqual(opener.open.call_args.kwargs["timeout"], 10)

    def test_rejects_sandbox_missing_environment_and_mismatched_backend(self):
        for overrides in ({"storeEnvironment": "sandbox"}, {"storeEnvironment": None},
                          {"storeEnvironment": "unknown"}, {"source": "app_store"},
                          {"ready": False}, {"ready": 1}, {"productId": "other"},
                          {"licensePublicKey": "mismatch"}, {"licensePublicKey": 123}):
            with self.subTest(overrides=overrides):
                opener = self.opener(self.backend_response(**overrides))
                with patch.object(release, "build_opener", return_value=opener):
                    with self.assertRaises(release.ReleaseError):
                        release.check_backend(self.values, "android")

    def test_backend_rejects_error_status_malformed_and_oversize_body(self):
        for body, status in ((b"{}", 503), (b"{invalid", 200), (b"[]", 200), (b"x" * 65537, 200)):
            with self.subTest(status=status, length=len(body)):
                opener = self.opener({}, status=status)
                opener.open.return_value.__enter__.return_value.read.return_value = body
                with patch.object(release, "build_opener", return_value=opener):
                    with self.assertRaises(release.ReleaseError):
                        release.check_backend(self.values, "android")

    def test_backend_failures_do_not_print_raw_response_or_endpoint(self):
        opener = self.opener({})
        opener.open.side_effect = OSError("receipt_private")
        with patch.object(release, "build_opener", return_value=opener):
            with self.assertRaises(release.ReleaseError) as error:
                release.check_backend(self.values, "android")
            self.assertNotIn("receipt_private", str(error.exception))
        self.assertIsNone(release._NoRedirects().redirect_request(None, None, 302, None, None, None))

    def test_failed_preflight_never_starts_flutter(self):
        self.signing_fixture()
        with patch.object(release, "ROOT", self.root), \
             patch.object(release, "check_backend", side_effect=release.ReleaseError("unavailable")), \
             patch.object(release.subprocess, "run") as run, redirect_stderr(io.StringIO()):
            self.assertEqual(release.main(["--platform", "android", "--defines-file",
                                           str(self.defines_file)]), 1)
            run.assert_not_called()

    def test_check_only_never_compiles_and_build_has_no_test_target_override(self):
        self.signing_fixture()
        with patch.object(release, "ROOT", self.root), \
             patch.object(release, "check_backend"), \
             patch.object(release.subprocess, "run") as run, redirect_stdout(io.StringIO()):
            args = ["--platform", "android", "--defines-file", str(self.defines_file)]
            self.assertEqual(release.main([*args, "--check-only"]), 0)
            run.assert_not_called()
            run.side_effect = lambda *args, **kwargs: (self.artifact_fixture("android"), SimpleNamespace(returncode=0))[1]
            self.assertEqual(release.main(args), 0)
            command = run.call_args.args[0]
            self.assertEqual(command[:3], ["flutter", "build", "appbundle"])
            self.assertIn("--target=lib/main.dart", command)
            self.assertIn("--release", command)
            self.assertNotIn("--no-codesign", command)
            self.assertNotIn(self.key, command)

    def artifact_fixture(self, platform, *, signed=True, payload=b"test manifest"):
        path = (self.root / "build/app/outputs/bundle/release/app-release.aab"
                if platform == "android" else self.root / "build/ios/ipa/MiuCam.ipa")
        path.parent.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(path, "w") as archive:
            if platform == "android":
                archive.writestr("BundleConfig.pb", b"config")
                archive.writestr("base/manifest/AndroidManifest.xml", payload)
                if signed:
                    archive.writestr("META-INF/RELEASE.RSA", b"signature fixture")
                    archive.writestr("META-INF/RELEASE.SF", b"manifest signature fixture")
            else:
                archive.writestr("Payload/Runner.app/Info.plist", payload)
                if signed:
                    archive.writestr("Payload/Runner.app/_CodeSignature/CodeResources", b"signature fixture")
        return path

    def test_zero_exit_with_no_ipa_or_old_ipa_is_failure(self):
        options = self.ios_fixture()
        with patch.object(release, "ROOT", self.root), \
             patch.object(release.sys, "platform", "darwin"), \
             patch.object(release, "check_backend"), \
             patch.object(release.subprocess, "run", return_value=SimpleNamespace(returncode=0)), \
             redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
            args = ["--platform", "ios", "--defines-file", str(self.defines_file),
                    "--export-options-plist", str(options)]
            self.assertEqual(release.main(args), 1)
            artifact = self.artifact_fixture("ios")
            original = artifact.read_bytes()
            self.assertEqual(release.main(args), 1)
            self.assertEqual(artifact.read_bytes(), original, "Existing IPA must not be deleted")

    def test_zero_exit_with_no_or_old_android_bundle_is_failure(self):
        self.signing_fixture()
        with patch.object(release, "ROOT", self.root), \
             patch.object(release, "check_backend"), \
             patch.object(release.subprocess, "run", return_value=SimpleNamespace(returncode=0)), \
             redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
            args = ["--platform", "android", "--defines-file", str(self.defines_file)]
            self.assertEqual(release.main(args), 1)
            artifact = self.artifact_fixture("android")
            original = artifact.read_bytes()
            self.assertEqual(release.main(args), 1)
            self.assertEqual(artifact.read_bytes(), original)

    def test_fresh_ipa_allows_success_without_upload_argument(self):
        options = self.ios_fixture(destination="export")
        def build(*args, **kwargs):
            self.artifact_fixture("ios")
            return SimpleNamespace(returncode=0)
        with patch.object(release, "ROOT", self.root), \
             patch.object(release.sys, "platform", "darwin"), \
             patch.object(release, "check_backend"), \
             patch.object(release.subprocess, "run", side_effect=build) as run, \
             redirect_stdout(io.StringIO()):
            self.assertEqual(release.main(["--platform", "ios", "--defines-file", str(self.defines_file),
                                         "--export-options-plist", str(options)]), 0)
            self.assertEqual(run.call_args.args[0][:3], ["flutter", "build", "ipa"])

    def test_new_unsigned_corrupt_and_empty_artifacts_are_rejected(self):
        for platform in ("android", "ios"):
            for kind in ("unsigned", "corrupt", "empty"):
                with self.subTest(platform=platform, kind=kind):
                    artifact = self.artifact_fixture(platform, signed=False)
                    if kind != "unsigned":
                        artifact.write_bytes(b"invalid archive" if kind == "corrupt" else b"")
                    with self.assertRaises(release.ReleaseError):
                        release.check_built_artifact(self.root, platform, {})

    def test_unchanged_artifacts_rejected_but_rebuilt_metadata_or_content_passes(self):
        for platform in ("android", "ios"):
            with self.subTest(platform=platform):
                artifact = self.artifact_fixture(platform)
                before = release.artifact_snapshot(self.root, platform)
                with self.assertRaises(release.ReleaseError):
                    release.check_built_artifact(self.root, platform, before)
                stat = artifact.stat()
                os.utime(artifact, ns=(stat.st_atime_ns, stat.st_mtime_ns + 1000000))
                release.check_built_artifact(self.root, platform, before)
                before = release.artifact_snapshot(self.root, platform)
                self.artifact_fixture(platform, payload=b"a new manifest")
                release.check_built_artifact(self.root, platform, before)

    def test_flutter_failure_propagates_and_missing_tool_returns_failure(self):
        self.signing_fixture()
        with patch.object(release, "ROOT", self.root), \
             patch.object(release, "check_backend"), \
             patch.object(release.subprocess, "run") as run, \
             redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
            args = ["--platform", "android", "--defines-file", str(self.defines_file)]
            run.return_value.returncode = 7
            self.assertEqual(release.main(args), 7)
            run.side_effect = FileNotFoundError()
            self.assertEqual(release.main(args), 1)


if __name__ == "__main__":
    unittest.main()
