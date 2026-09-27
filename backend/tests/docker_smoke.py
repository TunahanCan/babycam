"""Exercise the shipped image locally with synthetic purchases and no network.

Run from any directory with Python 3 and a running Docker daemon. The fixture is
copied to a temporary test volume, never built into the production image. No store
credentials, host ports, or real transactions are used.
"""
from __future__ import annotations

import argparse
from pathlib import Path
import subprocess
import tempfile
import time
import uuid


FIXTURE = '''
from pathlib import Path
from fastapi import Request
from miucam_billing.app import create_app
from miucam_billing.domain import StoreFailure, StorePurchase, fingerprint
from miucam_billing.licenses import LicenseRepository, LicenseSigner, PRODUCT_ID
from miucam_billing.service import BillingService

class Store:
    source = "google_play"
    def reference_from_evidence(self, evidence):
        if evidence != "synthetic-container-purchase":
            raise StoreFailure("rejected")
        return evidence
    def refresh(self, reference):
        self.reference_from_evidence(reference)
        path = Path("/data/store-state")
        state = path.read_text() if path.exists() else "active"
        if state == "unavailable":
            raise StoreFailure("transient")
        return StorePurchase(self.source, reference,
            fingerprint(self.source, "com.miucam.app", PRODUCT_ID, reference), state, True)

def factory():
    store = Store()
    service = BillingService(LicenseRepository("/data/licenses.sqlite3"),
        LicenseSigner.from_file("/data/signing.pem"), {store.source: store})
    app = create_app(service, run_recovery=False)
    @app.post("/fixture/state")
    async def state(request: Request):
        state = (await request.json())["state"]
        assert state in ("active", "revoked", "unavailable")
        Path("/data/store-state").write_text(state)
        return {"ok": True}
    return app
'''

HTTP_HELPERS = '''
import json, os, sqlite3, shutil, urllib.request, urllib.error
from pathlib import Path
from miucam_billing.licenses import LicenseSigner, PRODUCT_ID
assert os.getuid() == 10001
assert not Path("/app/tests").exists()
def request(path, payload=None, raw=None):
    data = json.dumps(payload).encode() if payload is not None else raw
    req = urllib.request.Request("http://127.0.0.1:8080" + path, data=data,
        headers={"Content-Type": "application/json"})
    try:
        response = urllib.request.urlopen(req, timeout=5)
    except urllib.error.HTTPError as error:
        response = error
    with response:
        assert response.headers.get("Cache-Control") == "no-store"
        return response.status, json.load(response)
purchase = {"source": "google_play", "productId": PRODUCT_ID,
            "serverVerificationData": "synthetic-container-purchase"}
'''


def run(*args: str, check: bool = True) -> subprocess.CompletedProcess:
    result = subprocess.run(args, text=True, capture_output=True)
    if check and result.returncode:
        raise RuntimeError(f"Command failed: {args[0:3]}\n{result.stderr}\n{result.stdout}")
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--image", default="miucam-billing:local-smoke")
    parser.add_argument("--skip-build", action="store_true")
    options = parser.parse_args()
    backend = Path(__file__).resolve().parents[1]
    suffix = uuid.uuid4().hex[:12]
    container, volume = f"miucam-smoke-{suffix}", f"miucam-smoke-data-{suffix}"
    if not options.skip_build:
        run("docker", "build", "--tag", options.image, str(backend))
    print("PASS: production image built", flush=True)
    # An unconfigured real entrypoint must stop, never enable a fixture backend.
    result = run("docker", "run", "--rm", "--network", "none", options.image, check=False)
    assert result.returncode != 0 and "Application startup failed" in result.stderr
    print("PASS: unconfigured production entrypoint fails closed", flush=True)
    run("docker", "volume", "create", volume)
    mount = f"type=volume,source={volume},target=/data"
    try:
        run("docker", "run", "--rm", "--network", "none", "--mount", mount,
            options.image, "python", "-c",
            "from pathlib import Path; from miucam_billing.keygen import generate; "
            "generate(Path('/data/signing.pem'))")
        with tempfile.TemporaryDirectory(prefix="miucam-container-fixture-") as temporary:
            fixture = Path(temporary)
            (fixture / "container_fixture.py").write_text(FIXTURE)
            run("docker", "create", "--name", container, "--network", "none",
                "--read-only", "--cap-drop", "ALL", "--security-opt", "no-new-privileges",
                "--mount", mount, "--env", "PYTHONPATH=/app:/data", options.image,
                "uvicorn", "container_fixture:factory", "--factory", "--host", "127.0.0.1",
                "--port", "8080", "--workers", "1", "--limit-concurrency", "64", "--no-access-log")
            # docker cp also works with Docker Desktop/remote daemons, where a
            # client-side temporary path cannot be used as a host bind mount.
            run("docker", "cp", str(fixture / "container_fixture.py"),
                f"{container}:/data/container_fixture.py")
            run("docker", "start", container)

            def check(code: str) -> None:
                run("docker", "exec", container, "python", "-c", HTTP_HELPERS + code)

            def ready() -> None:
                for _ in range(40):
                    result = run("docker", "exec", container, "python", "-c",
                        HTTP_HELPERS + 'assert request("/health")[0] == 200', check=False)
                    if result.returncode == 0:
                        return
                    time.sleep(0.25)
                raise RuntimeError("Container did not become ready")

            ready()
            run("docker", "exec", container, "python", "-m", "pip", "check")
            check('''
health = request("/health")[1]
assert health["sources"] == ["google_play"] and "storeEnvironment" not in health
preflight = request("/verify", {**purchase, "preflight": True})[1]
assert preflight["ready"] is True and "licenseToken" not in preflight
assert "storeEnvironment" not in preflight
assert request("/notifications/google", {})[0] == 401
assert request("/verify", raw=b"x" * (128 * 1024 + 1))[0] == 413
assert request("/verify", {**purchase, "productId": "wrong"})[1]["verified"] is False
status, first = request("/verify", purchase)
assert status == 200 and first["verified"] is True
signer = LicenseSigner.from_file("/data/signing.pem")
assert signer.verify(first["licenseToken"])["status"] == "active"
assert preflight["licensePublicKey"] == signer.public_key
assert purchase["serverVerificationData"] not in json.dumps(first)
Path("/data/first.json").write_text(json.dumps(first))
with sqlite3.connect("/data/licenses.sqlite3") as source:
    with sqlite3.connect("/data/backup.sqlite3") as backup:
        source.backup(backup)
shutil.copyfile("/data/signing.pem", "/data/backup.pem")
''')
            print("PASS: non-root/read-only image, HTTP purchase, signature, limits and safe SQLite backup", flush=True)
            run("docker", "restart", container)
            ready()
            check('''
first = json.loads(Path("/data/first.json").read_text())
status, refreshed = request("/verify", {"licenseToken": first["licenseToken"]})
assert status == 200 and refreshed["entitlementId"] == first["entitlementId"]
assert request("/verify", purchase)[1]["entitlementId"] == first["entitlementId"]
assert request("/fixture/state", {"state": "unavailable"})[0] == 200
assert request("/verify", {"licenseToken": first["licenseToken"]})[0] == 503
with sqlite3.connect("/data/licenses.sqlite3") as db:
    assert db.execute("SELECT status FROM licenses").fetchone()[0] == "active"
assert request("/fixture/state", {"state": "revoked"})[0] == 200
revoked = request("/verify", {"licenseToken": first["licenseToken"]})[1]
assert revoked["reasonCode"] == "revoked"
assert LicenseSigner.from_file("/data/signing.pem").verify(revoked["licenseToken"])["status"] == "revoked"
''')
            print("PASS: restart preserves key/entitlement; outage preserves access; refund produces signed revocation", flush=True)
            run("docker", "stop", container)
            run("docker", "run", "--rm", "--network", "none", "--mount", mount,
                options.image, "python", "-c", '''
from pathlib import Path
import shutil
for suffix in ("-wal", "-shm"):
    Path("/data/licenses.sqlite3" + suffix).unlink(missing_ok=True)
shutil.copyfile("/data/backup.sqlite3", "/data/licenses.sqlite3")
shutil.copyfile("/data/backup.pem", "/data/signing.pem")
''')
            run("docker", "start", container)
            ready()
            check('''
first = json.loads(Path("/data/first.json").read_text())
status, restored = request("/verify", {"licenseToken": first["licenseToken"]})
assert status == 200 and restored["entitlementId"] == first["entitlementId"]
assert restored["verified"] is False and restored["reasonCode"] == "revoked"
for _ in range(120):
    last_status, _ = request("/verify", {**purchase, "preflight": True})
assert last_status == 429
assert request("/health")[0] == 200
''')
            print("PASS: key/DB restore retains identity and reconciles refund; rate limit leaves health available", flush=True)
    except BaseException:
        logs = run("docker", "logs", "--tail", "30", container, check=False)
        print(logs.stderr)
        raise
    finally:
        run("docker", "rm", "--force", container, check=False)
        run("docker", "volume", "rm", volume, check=False)
    print("All container smoke checks passed; synthetic resources removed.", flush=True)


if __name__ == "__main__":
    main()
