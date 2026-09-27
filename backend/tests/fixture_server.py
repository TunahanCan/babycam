"""Loopback-only store double for Dart/Python protocol integration tests.

Never imported by the production app factory or copied into the Docker image.
"""
import json
import socket
import sys

import uvicorn
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

from miucam_billing.app import create_app
from miucam_billing.licenses import LicenseRepository, LicenseSigner, PRODUCT_ID, StorePurchase, fingerprint
from miucam_billing.service import BillingService
from miucam_billing.stores import StoreFailure


class FixtureStore:
    source = "google_play"
    revoked = False

    def reference_from_evidence(self, evidence):
        if evidence != "synthetic-integration-purchase":
            raise StoreFailure("rejected")
        return evidence

    def refresh(self, reference):
        self.reference_from_evidence(reference)
        return StorePurchase(self.source, reference,
                             fingerprint(self.source, "com.miucam.app", PRODUCT_ID, reference),
                             "revoked" if self.revoked else "active", True)


if __name__ == "__main__":
    store = FixtureStore()
    signer = LicenseSigner(Ed25519PrivateKey.generate())
    service = BillingService(LicenseRepository(sys.argv[1]), signer, {store.source: store})
    app = create_app(service, run_recovery=False)

    @app.post("/fixture/revoke")
    async def revoke():
        store.revoked = True
        return {"ok": True}

    listener = socket.socket()
    listener.bind(("127.0.0.1", 0))

    class FixtureServer(uvicorn.Server):
        async def startup(self, sockets=None):
            await super().startup(sockets=sockets)
            # Binding reserves the port, but does not yet accept connections.
            # Publish readiness only after ASGI startup and listener activation.
            print(json.dumps({"port": listener.getsockname()[1],
                              "publicKey": signer.public_key}), flush=True)

    server = FixtureServer(uvicorn.Config(app, log_level="error", access_log=False))
    server.run(sockets=[listener])
