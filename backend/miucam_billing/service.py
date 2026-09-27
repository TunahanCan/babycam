from __future__ import annotations

import threading
from contextlib import contextmanager

from .licenses import LicenseRepository, LicenseSigner
from .stores import StoreFailure


class BillingService:
    def __init__(self, repository: LicenseRepository, signer: LicenseSigner, stores: dict):
        self.repository = repository
        self.signer = signer
        self.stores = stores
        self._mutex = threading.Lock()
        self._operations = {}

    @contextmanager
    def _transaction(self, source: str, reference: str):
        # Serialize requests for the same store purchase, including notifications
        # and retries, so an older active response cannot overwrite a refund.
        key = (source, reference)
        with self._mutex:
            lock, users = self._operations.get(key, (threading.Lock(), 0))
            self._operations[key] = (lock, users + 1)
        acquired = lock.acquire(timeout=20)
        try:
            if not acquired:
                raise StoreFailure("transient")
            yield
        finally:
            if acquired:
                lock.release()
            with self._mutex:
                _, users = self._operations[key]
                if users == 1:
                    del self._operations[key]
                else:
                    self._operations[key] = (lock, users - 1)

    def _store(self, source):
        if not isinstance(source, str) or source not in ("google_play", "app_store"):
            raise StoreFailure("rejected")
        store = self.stores.get(source)
        if store is None:
            raise StoreFailure("configuration")
        return store

    def verify(self, body: dict) -> dict:
        token = body.get("licenseToken")
        if token is not None:
            claims = self.signer.verify(token)
            record = self.repository.get(claims["entitlementId"])
            if (record is None or record["fingerprint"] != claims["transactionFingerprint"]
                    or record["source"] != claims["source"]):
                # A restored database must not silently discard an offline paid
                # license. Treat unknown state as unavailable, not revocation.
                raise StoreFailure("transient")
            return self.reconcile(record["source"], record["reference"])
        if body.get("productId") != self.signer.product_id:
            raise StoreFailure("rejected")
        source = body.get("source")
        store = self._store(source)
        if body.get("preflight") is True:
            return {"ready": True, "source": source, "productId": self.signer.product_id,
                    "licensePublicKey": self.signer.public_key}
        evidence = body.get("serverVerificationData")
        if not isinstance(evidence, str) or not evidence or len(evidence) > 110_000:
            raise StoreFailure("rejected")
        reference = store.reference_from_evidence(evidence)
        return self.reconcile(source, reference)

    def reconcile(self, source: str, reference: str, *, acknowledge: bool = False) -> dict:
        store = self._store(source)
        with self._transaction(source, reference):
            purchase = store.refresh(reference)
            # SQLite commit precedes both the signed response and any fallback
            # store acknowledgement. A process crash cannot lose delivery.
            record = self.repository.save(purchase)
            if acknowledge and purchase.status == "active" and not purchase.acknowledged:
                store.acknowledge(reference)
                # Confirm the final state rather than assuming the POST won its
                # race with a cancellation. Uncertain results remain retryable.
                record = self.repository.save(store.refresh(reference))
            return self.response(record)

    def response(self, record: dict) -> dict:
        active = record["status"] == "active"
        result = {
            "verified": active, "source": record["source"], "productId": self.signer.product_id,
            "entitlementId": record["entitlement_id"], "transactionFingerprint": record["fingerprint"],
            "licenseToken": self.signer.sign(record),
        }
        if not active:
            result.update(reasonCode="revoked", reason="The store revoked this purchase.")
        return result

    def recover_acknowledgements(self):
        for record in self.repository.pending_acknowledgements():
            try:
                self.reconcile(record["source"], record["reference"], acknowledge=True)
            except StoreFailure:
                # Keep durable pending work. Do not log receipt URLs or tokens.
                # A repeatedly failing batch must not starve later purchases.
                self.repository.defer_acknowledgement(record["fingerprint"])
                continue
