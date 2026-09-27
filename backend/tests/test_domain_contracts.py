import json

import pytest
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from fastapi.testclient import TestClient

from miucam_billing.app import create_app
from miucam_billing.domain import (AcknowledgingStore, PurchaseStatus, SignedNotificationStore,
                                  StoreAdapter, StoreFailure, StorePurchase, StoreSource)
from miucam_billing.licenses import LicenseRepository, LicenseSigner
from miucam_billing.service import BillingService
from miucam_billing.stores import AppStore, GooglePlayStore, StoreConfig


class ReadOnlyStore:
    """Minimal structural adapter: no inheritance or unused store operations."""

    source = StoreSource.GOOGLE_PLAY

    def reference_from_evidence(self, evidence):
        return evidence

    def refresh(self, reference):
        return StorePurchase(self.source, reference, "a" * 64, PurchaseStatus.ACTIVE, False)


def service(tmp_path, stores):
    return BillingService(LicenseRepository(tmp_path / "licenses.sqlite3"),
                          LicenseSigner(Ed25519PrivateKey.generate()), stores)


def test_domain_values_preserve_the_existing_json_and_sqlite_contract(tmp_path):
    purchase = StorePurchase("google_play", "synthetic-reference", "a" * 64, "active")
    assert purchase.source is StoreSource.GOOGLE_PLAY
    assert purchase.status is PurchaseStatus.ACTIVE
    repository = LicenseRepository(tmp_path / "licenses.sqlite3")
    saved = repository.save(purchase)
    assert json.loads(json.dumps({"source": purchase.source, "status": purchase.status})) == {
        "source": "google_play", "status": "active"}
    assert saved["source"] == "google_play" and saved["status"] == "active"


@pytest.mark.parametrize("source,status", [("unknown", "active"), ("app_store", "pending")])
def test_unconfirmed_adapter_state_is_rejected_before_persistence(source, status):
    with pytest.raises(ValueError):
        StorePurchase(source, "synthetic-reference", "a" * 64, status)


def test_store_capabilities_are_structural_and_do_not_require_unrelated_operations():
    google = GooglePlayStore(StoreConfig(), session_factory=lambda: None)
    apple = AppStore(StoreConfig(), client=None, verifier=None)
    assert isinstance(google, StoreAdapter) and isinstance(apple, StoreAdapter)
    assert isinstance(google, AcknowledgingStore)
    assert not isinstance(apple, AcknowledgingStore)
    assert isinstance(apple, SignedNotificationStore)
    assert not isinstance(google, SignedNotificationStore)


def test_adapter_registry_is_stable_after_composition_and_rejects_mismatched_source(tmp_path):
    registry = {"google_play": ReadOnlyStore()}
    billing = service(tmp_path, registry)
    registry.clear()
    assert billing.available_sources == ("google_play",)
    with pytest.raises(TypeError):
        billing.stores["app_store"] = ReadOnlyStore()
    with pytest.raises(ValueError, match="registered source"):
        service(tmp_path, {"app_store": ReadOnlyStore()})


def test_missing_ack_capability_keeps_durable_purchase_retryable(tmp_path):
    billing = service(tmp_path, {"google_play": ReadOnlyStore()})
    with pytest.raises(StoreFailure, match="configuration"):
        billing.reconcile("google_play", "synthetic-reference", acknowledge=True)
    saved = billing.repository.find("google_play", "synthetic-reference")
    assert saved["status"] == "active" and saved["ack_pending"] == 1


def test_http_notification_and_health_use_only_the_public_use_case_boundary():
    class Boundary:
        available_sources = ("app_store",)
        product_id = "configured-product"
        store_environment = None
        notices = []

        def process_apple_notification(self, signed_payload):
            self.notices.append(signed_payload)

    boundary = Boundary()
    with TestClient(create_app(boundary, run_recovery=False)) as client:
        assert client.get("/health").json() == {
            "ok": True, "sources": ["app_store"], "productId": "configured-product"}
        response = client.post("/notifications/apple", json={"signedPayload": "synthetic-notification"})
    assert response.status_code == 200 and response.json() == {"ok": True}
    assert boundary.notices == ["synthetic-notification"]


def test_notification_capability_misconfiguration_returns_controlled_failure(tmp_path):
    class AppleReadOnlyStore(ReadOnlyStore):
        source = StoreSource.APP_STORE

    billing = service(tmp_path, {"app_store": AppleReadOnlyStore()})
    with TestClient(create_app(billing, run_recovery=False)) as client:
        response = client.post("/notifications/apple", json={"signedPayload": "synthetic-notification"})
    assert response.status_code == 503
    assert response.json()["reasonCode"] == "configuration"
