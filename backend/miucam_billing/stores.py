from __future__ import annotations

import json
import threading
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import quote

import requests
from appstoreserverlibrary.signed_data_verifier import VerificationException, VerificationStatus

from .domain import PRODUCT_ID, PurchaseStatus, StoreFailure, StorePurchase, StoreSource, fingerprint


@dataclass(frozen=True)
class StoreConfig:
    application_id: str = "com.miucam.app"
    product_id: str = PRODUCT_ID
    allow_test_purchases: bool = False


class GooglePlayStore:
    source = StoreSource.GOOGLE_PLAY
    base_url = "https://androidpublisher.googleapis.com/androidpublisher/v3/applications"

    def __init__(self, config: StoreConfig, credentials=None, session_factory=None):
        self.config = config
        if session_factory is None:
            from google.auth.transport.requests import AuthorizedSession
            if credentials is None:
                import google.auth
                credentials, _ = google.auth.default(scopes=["https://www.googleapis.com/auth/androidpublisher"])
            session_factory = lambda: AuthorizedSession(credentials, max_refresh_attempts=1, refresh_timeout=8)
        self.session_factory = session_factory

    def _request(self, method: str, path: str, **kwargs) -> dict:
        with self.session_factory() as session:
            try:
                response = session.request(method, f"{self.base_url}/{quote(self.config.application_id, safe='')}/{path}",
                                           timeout=(3, 8), allow_redirects=False, stream=True, **kwargs)
                with response:
                    if response.status_code in (400, 404, 410):
                        raise StoreFailure("rejected")
                    if response.status_code < 200 or response.status_code >= 300:
                        raise StoreFailure()
                    body = bytearray()
                    for chunk in response.iter_content(8192):
                        body.extend(chunk)
                        if len(body) > 65536:
                            raise StoreFailure()
                    decoded = json.loads(body) if body else {}
                    if not isinstance(decoded, dict):
                        raise StoreFailure()
                    return decoded
            except StoreFailure:
                raise
            except Exception:
                raise StoreFailure() from None

    def verify(self, evidence: str) -> StorePurchase:
        return self.refresh(self.reference_from_evidence(evidence))

    def reference_from_evidence(self, evidence: str) -> str:
        if not isinstance(evidence, str) or not 1 <= len(evidence) <= 8192:
            raise StoreFailure("rejected")
        return evidence

    def refresh(self, reference: str) -> StorePurchase:
        data = self._request("GET", f"purchases/productsv2/tokens/{quote(reference, safe='')}")
        lines = data.get("productLineItem", [])
        if (not isinstance(lines, list) or len(lines) != 1 or not isinstance(lines[0], dict)
                or lines[0].get("productId") != self.config.product_id):
            raise StoreFailure("rejected")
        if data.get("testPurchaseContext") is not None and not self.config.allow_test_purchases:
            raise StoreFailure("rejected")
        context = data.get("purchaseStateContext", {})
        if not isinstance(context, dict):
            raise StoreFailure("transient")
        state = context.get("purchaseState")
        if state == "PENDING":
            raise StoreFailure("transient")
        if state not in ("PURCHASED", "CANCELLED"):
            raise StoreFailure("rejected")
        offer = lines[0].get("productOfferDetails", {})
        if not isinstance(offer, dict):
            raise StoreFailure("transient")
        if (state == "PURCHASED" and
                (offer.get("consumptionState") == "CONSUMPTION_STATE_CONSUMED"
                 or offer.get("quantity", 1) != 1)):
            raise StoreFailure("rejected")
        revoked = state == "CANCELLED" or offer.get("refundableQuantity") == 0
        return StorePurchase(
            self.source, reference,
            fingerprint(self.source, self.config.application_id, self.config.product_id, reference),
            PurchaseStatus.REVOKED if revoked else PurchaseStatus.ACTIVE,
            data.get("acknowledgementState") == "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED",
        )

    def acknowledge(self, reference: str) -> None:
        self._request("POST", f"purchases/products/{quote(self.config.product_id, safe='')}/tokens/{quote(reference, safe='')}:acknowledge", json={})


class AppStore:
    source = StoreSource.APP_STORE

    def __init__(self, config: StoreConfig, client, verifier, receipt_utility=None):
        self.config = config
        self.client = client
        self.verifier = verifier
        self.receipt_utility = receipt_utility
        # Apple's verifier maintains its certificate cache. Serialize access to
        # it; store requests run in the API server's bounded worker pool.
        self._verify_lock = threading.Lock()

    @classmethod
    def configured(cls, config, *, signing_key_path, key_id, issuer_id,
                   root_certificate_paths, app_apple_id, environment):
        from appstoreserverlibrary.api_client import AppStoreServerAPIClient
        from appstoreserverlibrary.models.Environment import Environment
        from appstoreserverlibrary.receipt_utility import ReceiptUtility
        from appstoreserverlibrary.signed_data_verifier import SignedDataVerifier

        class BoundedAppleClient(AppStoreServerAPIClient):
            def _execute_request(self, method, url, params, headers, json, data):
                return requests.request(method, url, params=params, headers=headers,
                                        json=json, data=data, timeout=(3, 8), allow_redirects=False)

        selected_environment = Environment.SANDBOX if environment == "sandbox" else Environment.PRODUCTION
        roots = [Path(path).read_bytes() for path in root_certificate_paths]
        if not roots or (selected_environment == Environment.PRODUCTION and app_apple_id is None):
            raise ValueError("Apple verification requires root certificates and production appAppleId")
        verifier = SignedDataVerifier(roots, True, selected_environment, config.application_id, app_apple_id)
        client = BoundedAppleClient(Path(signing_key_path).read_bytes(), key_id, issuer_id,
                                    config.application_id, selected_environment)
        return cls(config, client, verifier, ReceiptUtility())

    def _decode(self, signed_transaction: str):
        try:
            with self._verify_lock:
                transaction = self.verifier.verify_and_decode_signed_transaction(signed_transaction)
        except VerificationException as error:
            raise StoreFailure("transient" if error.status == VerificationStatus.RETRYABLE_VERIFICATION_FAILURE
                               else "rejected") from None
        except Exception:
            # A verifier can fail because OCSP is unreachable; no entitlement is
            # granted, but an existing offline license is not revoked either.
            raise StoreFailure("transient") from None
        from appstoreserverlibrary.models.Type import Type
        if (transaction.bundleId != self.config.application_id
                or transaction.productId != self.config.product_id
                or transaction.type != Type.NON_CONSUMABLE
                or not transaction.transactionId or not transaction.originalTransactionId):
            raise StoreFailure("rejected")
        return transaction

    def verify(self, evidence: str) -> StorePurchase:
        return self.refresh(self.reference_from_evidence(evidence))

    def reference_from_evidence(self, evidence: str) -> str:
        try:
            if evidence.count(".") == 2:
                transaction_id = self._decode(evidence).originalTransactionId
            elif self.receipt_utility is not None:
                # Official Apple migration path for older app receipts. The
                # extracted identifier is only a lookup key, never proof: the
                # API response must still be Apple-signed and match this app/SKU.
                lookup_id = self.receipt_utility.extract_transaction_id_from_app_receipt(evidence)
                if not lookup_id:
                    raise StoreFailure("rejected")
                # Receipts may contain a restored child transaction ID. Resolve
                # it before BillingService locks the purchase, so restore and
                # notification use the same original-transaction lock. This
                # lookup is not a grant: reconcile refreshes again under lock.
                transaction_id = self.refresh(lookup_id).reference
            else:
                transaction_id = None
            if not transaction_id:
                raise StoreFailure("rejected")
            return transaction_id
        except StoreFailure:
            raise
        except Exception:
            raise StoreFailure("rejected") from None

    def refresh(self, reference: str) -> StorePurchase:
        try:
            response = self.client.get_transaction_info(reference)
        except Exception:
            raise StoreFailure("transient") from None
        transaction = self._decode(response.signedTransactionInfo)
        return StorePurchase(
            self.source, transaction.originalTransactionId,
            fingerprint(self.source, self.config.application_id, self.config.product_id,
                        transaction.originalTransactionId),
            PurchaseStatus.REVOKED if transaction.revocationDate is not None else PurchaseStatus.ACTIVE,
        )

    def notification_reference(self, signed_payload: str) -> str | None:
        try:
            with self._verify_lock:
                notification = self.verifier.verify_and_decode_notification(signed_payload)
            if not notification.data or not notification.data.signedTransactionInfo:
                return None
            return self._decode(notification.data.signedTransactionInfo).originalTransactionId
        except StoreFailure:
            raise
        except VerificationException as error:
            # A retryable certificate/OCSP outage must not acknowledge and lose
            # a valid Apple notification; the API maps transient to HTTP 503.
            raise StoreFailure("transient" if error.status == VerificationStatus.RETRYABLE_VERIFICATION_FAILURE
                               else "rejected") from None
        except Exception:
            raise StoreFailure("rejected") from None
