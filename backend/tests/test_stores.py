"""Real adapters with synthetic store transport and official Apple model objects.

No Google/Apple network is used. These tests cover our adapter contract, not
Apple's certificate verification or store account configuration.
"""

import json
import threading
from collections import deque
from concurrent.futures import ThreadPoolExecutor

import pytest
import requests
from appstoreserverlibrary.models.Data import Data
from appstoreserverlibrary.models.Environment import Environment
from appstoreserverlibrary.models.JWSTransactionDecodedPayload import JWSTransactionDecodedPayload
from appstoreserverlibrary.models.ResponseBodyV2DecodedPayload import ResponseBodyV2DecodedPayload
from appstoreserverlibrary.models.TransactionInfoResponse import TransactionInfoResponse
from appstoreserverlibrary.models.Type import Type
from appstoreserverlibrary.signed_data_verifier import VerificationException, VerificationStatus
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from fastapi.testclient import TestClient

from miucam_billing.app import create_app
from miucam_billing.licenses import PRODUCT_ID, LicenseRepository, LicenseSigner, fingerprint
from miucam_billing.service import BillingService
from miucam_billing.stores import AppStore, GooglePlayStore, StoreConfig, StoreFailure


@pytest.fixture(autouse=True)
def prohibit_store_network(monkeypatch):
    def fail(*args, **kwargs):
        raise AssertionError("Store contract tests must not use the network")
    monkeypatch.setattr(requests.sessions.Session, "request", fail)


class Response:
    def __init__(self, data=None, *, status=200, chunks=None):
        self.status_code = status
        self.chunks = chunks if chunks is not None else [json.dumps(data).encode()]
        self.closed = False

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.closed = True

    def iter_content(self, size):
        assert size == 8192
        yield from self.chunks


class GoogleTransport:
    def __init__(self, *responses):
        self.responses = deque(responses)
        self.calls = []
        self.closed = 0

    def __call__(self):
        return self

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.closed += 1

    def request(self, method, url, **kwargs):
        self.calls.append((method, url, kwargs))
        response = self.responses.popleft()
        if isinstance(response, Exception):
            raise response
        return response


def google_purchase(*, state="PURCHASED", product=PRODUCT_ID, acknowledged=False,
                    offer=None, **extra):
    return {
        "productLineItem": [{"productId": product, "productOfferDetails": {
            "quantity": 1, "refundableQuantity": 1,
            "consumptionState": "CONSUMPTION_STATE_YET_TO_BE_CONSUMED", **(offer or {}),
        }}],
        "purchaseStateContext": {"purchaseState": state},
        "acknowledgementState": "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED" if acknowledged else "ACKNOWLEDGEMENT_STATE_PENDING",
        **extra,
    }


def google_store(data, *, config=None):
    response = data if isinstance(data, Response) else Response(data)
    transport = GoogleTransport(response)
    return GooglePlayStore(config or StoreConfig(), session_factory=transport), transport, response


def test_google_uses_v2_current_status_and_never_consumes_lifetime_purchase():
    store, transport, response = google_store(google_purchase())
    token = "synthetic/token+with?reserved=#characters"
    result = store.verify(token)
    assert result.source == "google_play"
    assert result.reference == token
    assert result.fingerprint == fingerprint("google_play", "com.miucam.app", PRODUCT_ID, token)
    assert result.status == "active"
    assert result.acknowledged is False
    assert transport.calls == [("GET", GooglePlayStore.base_url +
                               "/com.miucam.app/purchases/productsv2/tokens/synthetic%2Ftoken%2Bwith%3Freserved%3D%23characters",
                               {"timeout": (3, 8), "allow_redirects": False, "stream": True})]
    assert transport.closed == 1 and response.closed


@pytest.mark.parametrize("state,reason", [("PENDING", "transient"),
                                         ("PURCHASE_STATE_UNSPECIFIED", "rejected"),
                                         (None, "rejected")])
def test_google_pending_or_unknown_purchase_never_grants(state, reason):
    store, _, _ = google_store(google_purchase(state=state))
    with pytest.raises(StoreFailure, match=reason):
        store.verify("synthetic-token")


@pytest.mark.parametrize("payload", [google_purchase(state="CANCELLED"),
                                    google_purchase(offer={"refundableQuantity": 0})])
def test_google_current_cancellation_and_quantity_refund_are_revoked(payload):
    store, _, _ = google_store(payload)
    assert store.verify("synthetic-token").status == "revoked"


@pytest.mark.parametrize("payload", [google_purchase(product="other-product"),
                                    google_purchase(productLineItem=[]),
                                    google_purchase(productLineItem=[{}, {}]),
                                    google_purchase(offer={"consumptionState": "CONSUMPTION_STATE_CONSUMED"}),
                                    google_purchase(offer={"quantity": 2})])
def test_google_rejects_wrong_sku_multiline_consumed_and_multi_quantity(payload):
    store, _, _ = google_store(payload)
    with pytest.raises(StoreFailure, match="rejected"):
        store.verify("synthetic-token")


def test_google_test_purchase_is_rejected_in_production_and_explicit_in_sandbox():
    payload = google_purchase(testPurchaseContext={"fopType": "TEST"}, acknowledged=True)
    production, _, _ = google_store(payload)
    with pytest.raises(StoreFailure, match="rejected"):
        production.verify("synthetic-token")
    sandbox, _, _ = google_store(payload, config=StoreConfig(allow_test_purchases=True))
    assert sandbox.verify("synthetic-token").acknowledged


def test_google_acknowledges_exact_product_path_with_empty_body_and_empty_response():
    response = Response(chunks=[])
    config = StoreConfig(application_id="synthetic/app", product_id="synthetic/product")
    store, transport, _ = google_store(response, config=config)
    store.acknowledge("synthetic/token")
    assert transport.calls == [("POST", GooglePlayStore.base_url +
                               "/synthetic%2Fapp/purchases/products/synthetic%2Fproduct/tokens/synthetic%2Ftoken:acknowledge",
                               {"timeout": (3, 8), "allow_redirects": False, "stream": True, "json": {}})]
    assert response.closed and transport.closed == 1


@pytest.mark.parametrize("status,reason", [(400, "rejected"), (404, "rejected"),
                                          (410, "rejected"), (302, "transient"),
                                          (401, "transient"), (429, "transient"),
                                          (500, "transient")])
def test_google_http_failures_fail_closed_with_retryable_classification(status, reason):
    store, transport, response = google_store(Response(status=status))
    with pytest.raises(StoreFailure, match=reason):
        store.verify("synthetic-token")
    assert response.closed and transport.closed == 1


@pytest.mark.parametrize("chunks", [[b"[1,2]"], [b"not-json"], [b"x" * 8192] * 9])
def test_google_malformed_or_oversized_response_is_bounded_and_closed(chunks):
    store, transport, response = google_store(Response(chunks=chunks))
    with pytest.raises(StoreFailure, match="transient"):
        store.verify("synthetic-token")
    assert response.closed and transport.closed == 1


def test_google_transport_exception_does_not_expose_receipt_in_public_error():
    transport = GoogleTransport(requests.Timeout("https://store/synthetic-secret-receipt"))
    store = GooglePlayStore(StoreConfig(), session_factory=transport)
    with pytest.raises(StoreFailure) as caught:
        store.verify("synthetic-token")
    assert str(caught.value) == "transient"
    assert caught.value.__suppress_context__
    assert transport.closed == 1


@pytest.mark.parametrize("evidence", [None, "", "x" * 8193])
def test_google_invalid_evidence_rejected_before_store_request(evidence):
    store, transport, _ = google_store(google_purchase())
    with pytest.raises(StoreFailure, match="rejected"):
        store.verify(evidence)
    assert transport.calls == []


def apple_transaction(**changes):
    return JWSTransactionDecodedPayload(
        **{"bundleId": "com.miucam.app", "productId": PRODUCT_ID,
           "type": Type.NON_CONSUMABLE, "transactionId": "synthetic-transaction",
           "originalTransactionId": "synthetic-original", "environment": Environment.PRODUCTION,
           **changes})


class AppleVerifier:
    def __init__(self, transactions, notification=None):
        self.transactions = transactions
        self.notification = notification
        self.calls = []

    def verify_and_decode_signed_transaction(self, signed):
        self.calls.append(signed)
        value = self.transactions[signed]
        if isinstance(value, Exception):
            raise value
        return value

    def verify_and_decode_notification(self, signed):
        self.calls.append(signed)
        if isinstance(self.notification, Exception):
            raise self.notification
        return self.notification


class AppleClient:
    def __init__(self, signed="fresh.signed.transaction", error=None):
        self.signed = signed
        self.error = error
        self.calls = []

    def get_transaction_info(self, reference):
        self.calls.append(reference)
        if self.error:
            raise self.error
        return TransactionInfoResponse(signedTransactionInfo=self.signed)


def test_apple_stale_device_jws_only_selects_reference_current_api_can_revoke():
    verifier = AppleVerifier({"stale.signed.transaction": apple_transaction(),
                              "fresh.signed.transaction": apple_transaction(revocationDate=1_800_000_000_000)})
    client = AppleClient()
    store = AppStore(StoreConfig(), client, verifier)
    result = store.verify("stale.signed.transaction")
    assert client.calls == ["synthetic-original"]
    assert verifier.calls == ["stale.signed.transaction", "fresh.signed.transaction"]
    assert result.source == "app_store"
    assert result.reference == "synthetic-original"
    assert result.status == "revoked"
    assert result.fingerprint == fingerprint("app_store", "com.miucam.app", PRODUCT_ID, "synthetic-original")


@pytest.mark.parametrize("change", [{"bundleId": "other.app"}, {"productId": "other-product"},
                                    {"type": Type.CONSUMABLE}, {"type": Type.AUTO_RENEWABLE_SUBSCRIPTION},
                                    {"transactionId": None}, {"originalTransactionId": None}])
def test_apple_signed_current_transaction_requires_app_sku_type_and_identity(change):
    verifier = AppleVerifier({"fresh.signed.transaction": apple_transaction(**change)})
    store = AppStore(StoreConfig(), AppleClient(), verifier)
    with pytest.raises(StoreFailure, match="rejected"):
        store.refresh("synthetic-original")


def test_apple_active_nonconsumable_purchase_is_acknowledged_by_app_store_contract():
    store = AppStore(StoreConfig(), AppleClient(),
                     AppleVerifier({"fresh.signed.transaction": apple_transaction()}))
    result = store.refresh("synthetic-original")
    assert result.status == "active" and result.acknowledged


@pytest.mark.parametrize("failure_at", ["client", "verifier"])
def test_apple_api_and_verifier_outages_are_transient_never_implicit_revocation(failure_at):
    failure = RuntimeError("synthetic-secret-receipt")
    client = AppleClient(error=failure if failure_at == "client" else None)
    verifier = AppleVerifier({"fresh.signed.transaction": failure if failure_at == "verifier" else apple_transaction()})
    store = AppStore(StoreConfig(), client, verifier)
    with pytest.raises(StoreFailure) as caught:
        store.refresh("synthetic-original")
    assert str(caught.value) == "transient" and caught.value.__suppress_context__


def test_apple_legacy_receipt_extraction_is_lookup_only_then_current_signed_validation():
    class Receipts:
        def extract_transaction_id_from_app_receipt(self, evidence):
            assert evidence == "synthetic-base64-app-receipt"
            return "synthetic-restored-child"
    client = AppleClient()
    verifier = AppleVerifier({"fresh.signed.transaction": apple_transaction(revocationDate=1)})
    store = AppStore(StoreConfig(), client, verifier, Receipts())
    assert store.verify("synthetic-base64-app-receipt").status == "revoked"
    assert client.calls == ["synthetic-restored-child", "synthetic-original"]
    assert verifier.calls == ["fresh.signed.transaction", "fresh.signed.transaction"]


def test_apple_legacy_restore_cannot_overwrite_concurrent_original_id_refund(tmp_path):
    lookup_started = threading.Event()
    release_lookup = threading.Event()

    class Client(AppleClient):
        def get_transaction_info(self, reference):
            self.calls.append(reference)
            if reference == "synthetic-restored-child":
                lookup_started.set()
                assert release_lookup.wait(3)
                return TransactionInfoResponse(signedTransactionInfo="stale.signed.transaction")
            return TransactionInfoResponse(signedTransactionInfo="fresh.signed.transaction")

    class Receipts:
        def extract_transaction_id_from_app_receipt(self, evidence):
            return "synthetic-restored-child"

    client = Client()
    verifier = AppleVerifier({"stale.signed.transaction": apple_transaction(),
                              "fresh.signed.transaction": apple_transaction(revocationDate=1)})
    store = AppStore(StoreConfig(), client, verifier, Receipts())
    service = BillingService(LicenseRepository(tmp_path / "licenses.sqlite3"),
                             LicenseSigner(Ed25519PrivateKey.generate()), {store.source: store})
    with ThreadPoolExecutor(max_workers=1) as executor:
        restoration = executor.submit(service.verify, {"productId": PRODUCT_ID, "source": "app_store",
                                                       "serverVerificationData": "synthetic-app-receipt"})
        assert lookup_started.wait(3)
        try:
            revoked = service.reconcile("app_store", "synthetic-original")
        finally:
            release_lookup.set()
        restored = restoration.result(3)
    # The old child response resolves identity only. A second, canonical query
    # inside the transaction lock decides entitlement and observes the refund.
    assert client.calls == ["synthetic-restored-child", "synthetic-original", "synthetic-original"]
    assert restored["entitlementId"] == revoked["entitlementId"]
    assert restored["verified"] is False
    assert service.repository.get(revoked["entitlementId"])["status"] == "revoked"
    assert service._operations == {}


def test_apple_unsupported_legacy_receipt_cannot_grant_without_api_verification():
    client = AppleClient()
    store = AppStore(StoreConfig(), client, AppleVerifier({}))
    with pytest.raises(StoreFailure, match="rejected"):
        store.verify("synthetic-base64-app-receipt")
    assert client.calls == []


def test_apple_notification_validates_both_envelope_and_embedded_transaction():
    notification = ResponseBodyV2DecodedPayload(data=Data(signedTransactionInfo="notice.signed.transaction"))
    verifier = AppleVerifier({"notice.signed.transaction": apple_transaction()}, notification)
    client = AppleClient()
    store = AppStore(StoreConfig(), client, verifier)
    assert store.notification_reference("signed.notification.envelope") == "synthetic-original"
    assert verifier.calls == ["signed.notification.envelope", "notice.signed.transaction"]
    assert client.calls == []  # BillingService reconciles the returned lookup key.


def test_apple_notification_without_purchase_has_no_activation_effect():
    store = AppStore(StoreConfig(), AppleClient(), AppleVerifier({}, ResponseBodyV2DecodedPayload()))
    assert store.notification_reference("signed.test.notification") is None


@pytest.mark.parametrize("failure_at", ["envelope", "transaction"])
@pytest.mark.parametrize("status,http_status,reason", [
    (VerificationStatus.RETRYABLE_VERIFICATION_FAILURE, 503, "transient"),
    (VerificationStatus.INVALID_CERTIFICATE, 200, "rejected"),
    (VerificationStatus.INVALID_APP_IDENTIFIER, 200, "rejected"),
])
def test_apple_notification_retries_certificate_outage_without_acknowledging_loss(
        tmp_path, failure_at, status, http_status, reason):
    error = VerificationException(status)
    notification = ResponseBodyV2DecodedPayload(data=Data(signedTransactionInfo="notice.signed.transaction"))
    verifier = AppleVerifier({"notice.signed.transaction": error},
                              error if failure_at == "envelope" else notification)
    store = AppStore(StoreConfig(), AppleClient(), verifier)
    service = BillingService(LicenseRepository(tmp_path / "licenses.sqlite3"),
                             LicenseSigner(Ed25519PrivateKey.generate()), {store.source: store})
    with TestClient(create_app(service, run_recovery=False)) as client:
        response = client.post("/notifications/apple", json={"signedPayload": "synthetic-notification"})
    assert response.status_code == http_status
    assert response.json()["reasonCode"] == reason
    assert store.client.calls == []


def test_apple_configured_client_keeps_official_verifier_online_and_api_bounded(tmp_path, monkeypatch):
    key = tmp_path / "synthetic-signing-key.pem"
    root = tmp_path / "synthetic-root.cer"
    key.write_bytes(ec.generate_private_key(ec.SECP256R1()).private_bytes(
        serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))
    root.write_bytes(b"synthetic-root-never-used-for-verification")
    store = AppStore.configured(StoreConfig(), signing_key_path=str(key), key_id="test-key",
                                issuer_id="test-issuer", root_certificate_paths=[str(root)],
                                app_apple_id=123, environment="production")
    assert store.verifier._environment == Environment.PRODUCTION
    assert store.verifier._enable_online_checks is True
    assert store.verifier._app_apple_id == 123
    calls = []
    sentinel = object()
    def request(*args, **kwargs):
        calls.append((args, kwargs))
        return sentinel
    monkeypatch.setattr(requests, "request", request)
    result = store.client._execute_request("GET", "https://synthetic.invalid", {}, {}, None, None)
    assert result is sentinel
    assert calls[0][1]["timeout"] == (3, 8)
    assert calls[0][1]["allow_redirects"] is False


@pytest.mark.parametrize("roots,apple_id", [([], 123), (["root"], None)])
def test_apple_production_configuration_requires_trust_roots_and_app_identity(tmp_path, roots, apple_id):
    root = tmp_path / "root"
    root.write_bytes(b"synthetic-root")
    with pytest.raises(ValueError, match="requires root certificates"):
        AppStore.configured(StoreConfig(), signing_key_path="unused", key_id="test", issuer_id="test",
                            root_certificate_paths=[str(tmp_path / path) for path in roots],
                            app_apple_id=apple_id, environment="production")
