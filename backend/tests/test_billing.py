import concurrent.futures
import json
import sqlite3
import threading

import pytest
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from fastapi.testclient import TestClient

from miucam_billing.app import create_app, configured_service
from miucam_billing.licenses import LicenseRepository, LicenseSigner, PRODUCT_ID, StorePurchase, b64, fingerprint
from miucam_billing.service import BillingService
from miucam_billing.stores import StoreFailure


class Store:
    source = "google_play"

    def __init__(self):
        self.state = "active"
        self.acknowledged = False
        self.failure = None
        self.acknowledgements = []
        self.refresh_calls = 0

    def reference_from_evidence(self, evidence):
        return evidence

    def refresh(self, reference):
        self.refresh_calls += 1
        if self.failure:
            raise StoreFailure(self.failure)
        return StorePurchase(self.source, reference,
                             fingerprint(self.source, "com.miucam.app", PRODUCT_ID, reference),
                             self.state, self.acknowledged)

    def acknowledge(self, reference):
        self.acknowledgements.append(reference)
        self.acknowledged = True


@pytest.fixture
def billing(tmp_path):
    clock = [1_800_000_000_000]
    repo = LicenseRepository(tmp_path / "licenses.sqlite3", clock_ms=lambda: clock[0])
    signer = LicenseSigner(Ed25519PrivateKey.generate())
    store = Store()
    service = BillingService(repo, signer, {store.source: store})
    service.test_clock = clock
    return service


def purchase(**overrides):
    return {"source": "google_play", "productId": PRODUCT_ID,
            "serverVerificationData": "synthetic-store-token", **overrides}


def test_checkout_preflight_reports_real_source_and_key_without_grant(billing):
    response = billing.verify(purchase(preflight=True))
    assert response == {"ready": True, "source": "google_play", "productId": PRODUCT_ID,
                        "licensePublicKey": billing.signer.public_key}
    assert "licenseToken" not in response
    assert billing.stores["google_play"].refresh_calls == 0


def test_verified_purchase_is_durable_before_response_and_survives_restart(billing):
    response = billing.verify(purchase())
    claims = billing.signer.verify(response["licenseToken"])
    assert claims["status"] == "active"
    assert claims["transactionFingerprint"] == response["transactionFingerprint"]
    restarted = LicenseRepository(billing.repository.path)
    assert restarted.get(response["entitlementId"])["reference"] == "synthetic-store-token"
    assert "synthetic-store-token" not in json.dumps(response)
    assert billing.stores["google_play"].acknowledgements == []


def test_concurrent_duplicate_delivery_keeps_one_entitlement_and_new_revisions(billing):
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        responses = list(pool.map(lambda _: billing.verify(purchase()), range(20)))
    assert len({r["entitlementId"] for r in responses}) == 1
    assert len({billing.signer.verify(r["licenseToken"])["issuedAtMs"] for r in responses}) == 20
    assert billing._operations == {}


def test_refund_refresh_uses_store_and_returns_signed_revocation(billing):
    first = billing.verify(purchase())
    billing.stores["google_play"].state = "revoked"
    revoked = billing.verify({"licenseToken": first["licenseToken"]})
    assert revoked["verified"] is False
    assert revoked["reasonCode"] == "revoked"
    assert revoked["entitlementId"] == first["entitlementId"]
    assert billing.signer.verify(revoked["licenseToken"])["status"] == "revoked"
    assert billing.stores["google_play"].refresh_calls == 2


def test_transient_store_failure_does_not_revoke_or_overwrite_existing_right(billing):
    first = billing.verify(purchase())
    billing.stores["google_play"].failure = "transient"
    with pytest.raises(StoreFailure, match="transient"):
        billing.verify({"licenseToken": first["licenseToken"]})
    assert billing.repository.get(first["entitlementId"])["status"] == "active"


def test_unknown_license_after_database_loss_is_transient_not_revocation(billing):
    first = billing.verify(purchase())
    with billing.repository.connection() as db:
        db.execute("DELETE FROM licenses")
    with pytest.raises(StoreFailure, match="transient"):
        billing.verify({"licenseToken": first["licenseToken"]})


def test_clock_rollback_never_rolls_back_license_revision(billing):
    first = billing.verify(purchase())
    billing.test_clock[0] -= 100_000
    second = billing.verify(purchase())
    assert billing.signer.verify(second["licenseToken"])["issuedAtMs"] > billing.signer.verify(first["licenseToken"])["issuedAtMs"]


def test_delayed_server_ack_recovers_when_app_never_returns(billing):
    first = billing.verify(purchase())
    billing.recover_acknowledgements()
    store = billing.stores["google_play"]
    assert store.acknowledgements == []
    billing.test_clock[0] += 31_000
    billing.recover_acknowledgements()
    assert store.acknowledgements == ["synthetic-store-token"]
    assert billing.repository.get(first["entitlementId"])["ack_pending"] == 0


def test_ack_recovery_checks_refunds_and_never_acknowledges_revoked_purchase(billing):
    first = billing.verify(purchase())
    billing.test_clock[0] += 31_000
    store = billing.stores["google_play"]
    store.state = "revoked"
    billing.recover_acknowledgements()
    assert store.acknowledgements == []
    assert billing.repository.get(first["entitlementId"])["status"] == "revoked"


def test_failed_ack_is_retried_from_durable_record(billing):
    first = billing.verify(purchase())
    billing.test_clock[0] += 31_000
    store = billing.stores["google_play"]
    original = store.acknowledge
    store.acknowledge = lambda _: (_ for _ in ()).throw(StoreFailure())
    billing.recover_acknowledgements()
    assert billing.repository.get(first["entitlementId"])["ack_pending"] == 1
    store.acknowledge = original
    billing.test_clock[0] += 31_000
    billing.recover_acknowledgements()
    assert len(store.acknowledgements) == 1


def test_failed_ack_batch_rotates_durably_without_changing_signed_entitlements(billing):
    store = billing.stores["google_play"]
    blocked_records = []
    for index in range(20):
        reference = f"synthetic-blocked-{index}"
        blocked_records.append(billing.repository.save(StorePurchase(
            "google_play", reference, fingerprint("google_play", "com.miucam.app", PRODUCT_ID, reference),
            "active", False)))
        billing.test_clock[0] += 1
    ready = billing.verify(purchase(serverVerificationData="synthetic-ready"))
    original_refresh = store.refresh

    def refresh(reference):
        if reference.startswith("synthetic-blocked-"):
            raise StoreFailure("transient")
        return original_refresh(reference)

    store.refresh = refresh
    billing.test_clock[0] += 31_000
    billing.recover_acknowledgements()
    assert store.acknowledgements == []  # First bounded batch contained 20 failures.
    for before in blocked_records:
        after = billing.repository.get(before["entitlement_id"])
        assert after["checked_at_ms"] == billing.test_clock[0]
        assert {k: v for k, v in after.items() if k != "checked_at_ms"} == {
            k: v for k, v in before.items() if k != "checked_at_ms"}

    # Restart before the next pass: retry ordering must be durable, and the
    # next eligible payment can be acknowledged without another 30-second wait.
    restarted = BillingService(LicenseRepository(billing.repository.path,
                               clock_ms=lambda: billing.test_clock[0]), billing.signer, billing.stores)
    restarted.recover_acknowledgements()
    assert store.acknowledgements == ["synthetic-ready"]
    assert billing.repository.get(ready["entitlementId"])["ack_pending"] == 0
    assert len(billing.repository.pending_acknowledgements()) == 0
    billing.test_clock[0] += 31_000
    assert len(billing.repository.pending_acknowledgements()) == 20


def test_storage_failure_cannot_acknowledge_or_publish_license(billing, monkeypatch):
    monkeypatch.setattr(billing.repository, "save", lambda _: (_ for _ in ()).throw(sqlite3.OperationalError("disk full")))
    with pytest.raises(sqlite3.OperationalError):
        billing.reconcile("google_play", "synthetic-store-token", acknowledge=True)
    assert billing.stores["google_play"].acknowledgements == []


@pytest.mark.parametrize("field,value", [("aud", "other-app"), ("version", True), ("status", "pending"),
                                         ("productId", "other-product"), ("issuedAtMs", 0)])
def test_even_signed_invalid_claims_are_rejected(billing, field, value):
    response = billing.verify(purchase())
    token = response["licenseToken"]
    claims = billing.signer.verify(token)
    claims[field] = value
    header = token.split(".")[0]
    body = b64(json.dumps(claims).encode())
    message = f"{header}.{body}"
    altered = f"{message}.{b64(billing.signer.private_key.sign(message.encode()))}"
    with pytest.raises(ValueError):
        billing.signer.verify(altered)


def test_wrong_key_and_unsigned_payload_cannot_refresh_license(billing):
    first = billing.verify(purchase())
    with pytest.raises(ValueError):
        LicenseSigner(Ed25519PrivateKey.generate()).verify(first["licenseToken"])
    with pytest.raises(ValueError):
        billing.verify({"licenseToken": '{"unlocked":true}'})


def test_api_purchase_preflight_refresh_and_no_store_headers(billing):
    with TestClient(create_app(billing, run_recovery=False)) as client:
        assert client.post("/verify", json=purchase(preflight=True)).json()["ready"]
        response = client.post("/verify", json=purchase())
        assert response.status_code == 200
        assert response.headers["cache-control"] == "no-store"
        billing.stores["google_play"].state = "revoked"
        refresh = client.post("/verify", json={"licenseToken": response.json()["licenseToken"]})
        assert refresh.json()["reasonCode"] == "revoked"


@pytest.mark.parametrize("body", [[], {"source": []}, {"source": "unknown", "productId": PRODUCT_ID},
                                   {"licenseToken": {}}, {"licenseToken": "not-a-token"}, purchase(productId="wrong")])
def test_api_bad_input_fails_closed_without_crashing(billing, body):
    with TestClient(create_app(billing, run_recovery=False)) as client:
        response = client.post("/verify", json=body)
        assert response.status_code == 200
        assert response.json()["verified"] is False


def test_api_body_limit_and_missing_store_fail_before_charge(billing):
    with TestClient(create_app(billing, run_recovery=False)) as client:
        assert client.post("/verify", content=b"a" * (128 * 1024 + 1)).status_code == 413
        response = client.post("/verify", json=purchase(preflight=True, source="app_store"))
        assert response.status_code == 503
        assert response.json()["reasonCode"] == "configuration"


def test_api_transient_failure_preserves_stored_license(billing):
    first = billing.verify(purchase())
    billing.stores["google_play"].failure = "transient"
    with TestClient(create_app(billing, run_recovery=False)) as client:
        response = client.post("/verify", json={"licenseToken": first["licenseToken"]})
        assert response.status_code == 503
        assert "licenseToken" not in response.json()
    assert billing.repository.get(first["entitlementId"])["status"] == "active"


def test_authenticated_google_notification_rechecks_store_and_revokes(billing):
    import base64
    first = billing.verify(purchase())
    billing.stores["google_play"].state = "revoked"
    def authenticate(value):
        if value != "Bearer verified-google-oidc":
            raise ValueError()
    data = base64.b64encode(json.dumps({"packageName": "com.miucam.app", "oneTimeProductNotification": {
        "purchaseToken": "synthetic-store-token", "sku": PRODUCT_ID,
    }}).encode()).decode()
    with TestClient(create_app(billing, run_recovery=False, google_notification_auth=authenticate)) as client:
        request = {"message": {"data": data}}
        assert client.post("/notifications/google", json=request).status_code == 401
        assert billing.repository.get(first["entitlementId"])["status"] == "active"
        assert client.post("/notifications/google", json=request,
                           headers={"Authorization": "Bearer verified-google-oidc"}).status_code == 200
    assert billing.repository.get(first["entitlementId"])["status"] == "revoked"


def test_unconfigured_production_service_never_falls_back_to_fake_verification(monkeypatch):
    monkeypatch.delenv("MIUCAM_LICENSE_PRIVATE_KEY_FILE", raising=False)
    with pytest.raises(KeyError):
        configured_service()


@pytest.mark.parametrize("payload", [[], 1, {"packageName": "com.miucam.app", "oneTimeProductNotification": [1]}])
def test_google_notification_malformed_nested_data_is_rejected(billing, payload):
    import base64
    data = base64.b64encode(json.dumps(payload).encode()).decode()
    with TestClient(create_app(billing, run_recovery=False, google_notification_auth=lambda _: None)) as client:
        assert client.post("/notifications/google", json={"message": {"data": data}}).status_code == 400
