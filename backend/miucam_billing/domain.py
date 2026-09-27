"""Store-independent purchase contracts shared by adapters and use cases.

Enums keep the existing JSON/SQLite string values. Structural protocols describe
only the capabilities a use case needs; Apple is not required to implement a
Google acknowledgement method.
"""

from __future__ import annotations

import hashlib
from dataclasses import dataclass
from enum import StrEnum
from typing import Protocol, runtime_checkable

PRODUCT_ID = "miucam_lifetime_unlock_try_300"


class StoreSource(StrEnum):
    GOOGLE_PLAY = "google_play"
    APP_STORE = "app_store"


class PurchaseStatus(StrEnum):
    ACTIVE = "active"
    REVOKED = "revoked"


class StoreFailureReason(StrEnum):
    TRANSIENT = "transient"
    REJECTED = "rejected"
    CONFIGURATION = "configuration"


class StoreFailure(Exception):
    def __init__(self, reason: StoreFailureReason | str = StoreFailureReason.TRANSIENT):
        # Never retain an upstream exception: its URL can contain a receipt.
        self.reason = StoreFailureReason(reason)
        super().__init__(self.reason.value)


@dataclass(frozen=True)
class StorePurchase:
    source: StoreSource
    reference: str
    fingerprint: str
    status: PurchaseStatus
    acknowledged: bool = True

    def __post_init__(self):
        # Accept existing string-based adapters while rejecting unknown states
        # before they can reach persistence or the license signer.
        object.__setattr__(self, "source", StoreSource(self.source))
        object.__setattr__(self, "status", PurchaseStatus(self.status))


def fingerprint(source: str, application: str, product: str, reference: str) -> str:
    return hashlib.sha256("\0".join((source, application, product, reference)).encode()).hexdigest()


@runtime_checkable
class StoreAdapter(Protocol):
    @property
    def source(self) -> StoreSource | str: ...

    def reference_from_evidence(self, evidence: str) -> str:
        """Resolve the canonical purchase identity before reconciliation locks."""
        ...

    def refresh(self, reference: str) -> StorePurchase:
        """Query the current store state; device evidence alone cannot grant."""
        ...


@runtime_checkable
class AcknowledgingStore(Protocol):
    def acknowledge(self, reference: str) -> None: ...


@runtime_checkable
class SignedNotificationStore(Protocol):
    def notification_reference(self, signed_payload: str) -> str | None: ...
