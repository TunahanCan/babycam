#!/usr/bin/env python3
"""Build a store artifact only after validating its production configuration.

This does not upload anything or certify real-store/device acceptance. Ordinary
`flutter build ... --release` remains available for compile-only CI checks.
"""
from __future__ import annotations

import argparse
import base64
import json
import hashlib
import ipaddress
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import zipfile
from urllib.parse import urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener

ROOT = Path(__file__).resolve().parents[2]
PRODUCT_ID = "miucam_lifetime_unlock_try_300"
SOURCES = {"android": "google_play", "ios": "app_store"}
ALLOWED_DEFINES = {
    "MIUCAM_PURCHASE_VERIFIER_URL", "MIUCAM_LICENSE_PUBLIC_KEY",
    "MIUCAM_BROADCAST_PAYWALL_ENABLED", "MIUCAM_WEBRTC_PILOT",
}


class ReleaseError(Exception):
    """A safe-to-display error that never contains configuration values."""


def load_defines(path: Path) -> dict[str, str]:
    try:
        values = json.loads(path.read_text())
    except (OSError, ValueError):
        raise ReleaseError("Provide a readable JSON production defines file.") from None
    if not isinstance(values, dict) or any(
        not isinstance(key, str) or not isinstance(value, (str, bool))
        for key, value in values.items()
    ):
        raise ReleaseError("Production defines must be a JSON object of strings/booleans.")
    if set(values) - ALLOWED_DEFINES:
        raise ReleaseError("Production defines contain an unsupported build override.")
    normalized = {key: str(value).lower() if isinstance(value, bool) else value
                  for key, value in values.items()}
    if normalized.get("MIUCAM_BROADCAST_PAYWALL_ENABLED", "true") != "true":
        raise ReleaseError("Production builds must keep the two-hour trial enabled.")
    if normalized.get("MIUCAM_WEBRTC_PILOT", "false") != "false":
        raise ReleaseError("The diagnostic WebRTC pilot is not a production build option.")
    endpoint = normalized.get("MIUCAM_PURCHASE_VERIFIER_URL", "")
    try:
        uri = urlsplit(endpoint)
        hostname = (uri.hostname or "").lower()
        valid_url = (uri.scheme == "https" and hostname and uri.port in (None, 443)
                     and uri.username is None and uri.password is None and not uri.fragment
                     and not uri.query and uri.path.endswith("/verify")
                     and endpoint == endpoint.strip()
                     and not any(char.isspace() for char in endpoint))
    except ValueError:
        valid_url = False
        hostname = ""
    try:
        public_address = ipaddress.ip_address(hostname).is_global
    except ValueError:
        public_address = True
    placeholders = ("localhost", "example.com", "example.org", "example.net")
    if (not valid_url or not public_address or "." not in hostname
            or any(hostname == host or hostname.endswith("." + host) for host in placeholders)
            or hostname.endswith((".local", ".test", ".invalid"))
            or "your-" in hostname or "your_" in hostname):
        raise ReleaseError("Set a real public HTTPS /verify endpoint without credentials or query data.")
    key = normalized.get("MIUCAM_LICENSE_PUBLIC_KEY", "")
    if not re.fullmatch(r"[A-Za-z0-9_-]{43}=?", key):
        raise ReleaseError("Set the backend's 32-byte base64url Ed25519 public key.")
    try:
        raw_key = base64.urlsafe_b64decode(key.rstrip("=") + "=")
    except ValueError:
        raise ReleaseError("Invalid Ed25519 public key encoding.") from None
    if (len(raw_key) != 32 or not any(raw_key)
            or base64.urlsafe_b64encode(raw_key).decode().rstrip("=") != key.rstrip("=")):
        raise ReleaseError("Invalid Ed25519 public key encoding.")
    return normalized


def check_android_signing(root: Path) -> None:
    try:
        text = (root / "android/key.properties").read_text()
    except OSError:
        raise ReleaseError("Android upload signing is missing: configure android/key.properties.") from None
    # Match the repository's key.properties template. Do not print its contents.
    properties = {}
    for line in text.splitlines():
        if not line.strip() or line.lstrip().startswith(("#", "!")):
            continue
        key, separator, value = line.partition("=")
        if not separator or value.rstrip().endswith("\\"):
            raise ReleaseError("Use single-line key=value signing properties as in the template.")
        properties[key.strip()] = value.strip().replace("\\\\", "\\").replace("\\:", ":")
    required = ("storeFile", "storePassword", "keyAlias", "keyPassword")
    if any(not properties.get(key) or properties[key] == "replace-me" for key in required):
        raise ReleaseError("Android upload signing properties are incomplete.")
    if properties["keyAlias"].lower() == "androiddebugkey":
        raise ReleaseError("The Android debug key cannot sign a production upload.")
    key_file = Path(properties["storeFile"])
    if not key_file.is_absolute():
        key_file = root / "android" / key_file
    try:
        exists = key_file.is_file() and key_file.stat().st_size > 0
    except OSError:
        exists = False
    if not exists:
        raise ReleaseError("The configured Android upload keystore is missing or empty.")


def check_ios_signing(root: Path, export_options: Path | None) -> None:
    if sys.platform != "darwin":
        raise ReleaseError("A signed iOS artifact requires macOS and Xcode.")
    if export_options is None:
        raise ReleaseError("iOS production builds require --export-options-plist.")
    try:
        options = plistlib.loads(export_options.read_bytes())
        project = (root / "ios/Runner.xcodeproj/project.pbxproj").read_text()
    except (OSError, ValueError, plistlib.InvalidFileException):
        raise ReleaseError("Read the Xcode project and App Store export options before building.") from None
    if not isinstance(options, dict):
        raise ReleaseError("The iOS export options must be a plist dictionary.")
    team = options.get("teamID", "")
    teams = re.findall(r"DEVELOPMENT_TEAM\s*=\s*\"?([A-Z0-9]{10})\"?\s*;", project)
    if not isinstance(team, str) or not re.fullmatch(r"[A-Z0-9]{10}", team) or team not in teams:
        raise ReleaseError("Configure the same Apple Developer Team in Xcode and export options.")
    if options.get("method") not in ("app-store-connect", "app-store"):
        raise ReleaseError("iOS export options must select App Store distribution.")
    if options.get("destination", "export") != "export":
        raise ReleaseError("Production builds only export locally; App Store upload is a separate action.")


class _NoRedirects(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def check_backend(defines: dict[str, str], platform: str) -> None:
    """Read-only billing preflight. No receipt, purchase, or license is created."""
    request = Request(
        defines["MIUCAM_PURCHASE_VERIFIER_URL"], method="POST",
        data=json.dumps({"preflight": True, "source": SOURCES[platform],
                         "productId": PRODUCT_ID}).encode(),
        headers={"Content-Type": "application/json", "Accept": "application/json"},
    )
    try:
        with build_opener(_NoRedirects()).open(request, timeout=10) as response:
            body = response.read(65537)
            if response.status != 200 or len(body) > 65536:
                raise ValueError()
            result = json.loads(body)
    except Exception:
        raise ReleaseError("Billing preflight failed; check the HTTPS verifier and enabled store.") from None
    if (not isinstance(result, dict) or result.get("ready") is not True
            or result.get("storeEnvironment") != "production"
            or result.get("source") != SOURCES[platform]
            or result.get("productId") != PRODUCT_ID
            or not isinstance(result.get("licensePublicKey"), str)
            or result["licensePublicKey"].rstrip("=")
            != defines["MIUCAM_LICENSE_PUBLIC_KEY"].rstrip("=")):
        raise ReleaseError("Billing preflight did not match the app's store, product, and public key.")


def artifact_snapshot(root: Path, platform: str) -> dict[Path, tuple]:
    candidates = ([root / "build/app/outputs/bundle/release/app-release.aab"]
                  if platform == "android" else sorted((root / "build/ios/ipa").glob("*.ipa")))
    result = {}
    for artifact in candidates:
        if not artifact.is_file():
            continue
        stat = artifact.stat()
        digest = hashlib.sha256()
        with artifact.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(chunk)
        result[artifact] = (stat.st_size, stat.st_mtime_ns, stat.st_ctime_ns,
                            stat.st_ino, digest.digest())
    return result


def check_built_artifact(root: Path, platform: str, before: dict[Path, tuple]) -> None:
    """Flutter can exit zero after an IPA export failure; inspect the output too."""
    after = artifact_snapshot(root, platform)
    fresh = [path for path, state in after.items() if state[0] > 0 and before.get(path) != state]
    if not fresh:
        raise ReleaseError("The build did not produce a new store artifact; existing files are not release evidence.")
    for path in fresh:
        try:
            with zipfile.ZipFile(path) as archive:
                names = {info.filename for info in archive.infolist() if info.file_size > 0}
                if platform == "android":
                    signed = any(name.startswith("META-INF/") and name.endswith((".RSA", ".DSA", ".EC"))
                                 for name in names)
                    valid = (signed and "BundleConfig.pb" in names
                             and "base/manifest/AndroidManifest.xml" in names
                             and any(name.startswith("META-INF/") and name.endswith(".SF") for name in names))
                else:
                    app_roots = {name[:-len("Info.plist")] for name in names
                                 if re.fullmatch(r"Payload/[^/]+\.app/Info\.plist", name)}
                    valid = any(app + "_CodeSignature/CodeResources" in names for app in app_roots)
                if not valid:
                    raise ReleaseError("The new artifact is not a signed store package.")
        except (OSError, zipfile.BadZipFile):
            raise ReleaseError("The new store artifact is missing, empty, or not a valid archive.") from None


def main(arguments: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--platform", choices=SOURCES, required=True)
    parser.add_argument("--defines-file", type=Path, required=True)
    parser.add_argument("--export-options-plist", type=Path)
    parser.add_argument("--flutter", default="flutter", help="Flutter executable path")
    parser.add_argument("--check-only", action="store_true",
                        help="Validate signing configuration and online billing without building")
    args = parser.parse_args(arguments)
    try:
        defines = load_defines(args.defines_file)
        if args.platform == "android":
            check_android_signing(ROOT)
        else:
            check_ios_signing(ROOT, args.export_options_plist)
        check_backend(defines, args.platform)
        print("Production configuration and billing preflight passed.")
        print("Physical-device and real-store purchase acceptance remain separate release gates.")
        if args.check_only:
            return 0
        command = [args.flutter, "build", "appbundle" if args.platform == "android" else "ipa",
                   "--release", "--target=lib/main.dart",
                   f"--dart-define-from-file={args.defines_file.resolve()}"]
        if args.platform == "ios":
            command.append(f"--export-options-plist={args.export_options_plist.resolve()}")
        before = artifact_snapshot(ROOT, args.platform)
        result = subprocess.run(command, cwd=ROOT, check=False)
        if result.returncode:
            return result.returncode
        check_built_artifact(ROOT, args.platform, before)
        print("A new signed store artifact was produced; nothing was uploaded.")
        return 0
    except ReleaseError as error:
        print(f"Production build blocked: {error}", file=sys.stderr)
        return 1
    except OSError:
        print("Production build blocked: required build tool could not be started.", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
