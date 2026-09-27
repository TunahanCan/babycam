from __future__ import annotations

import base64
import hashlib
import json
import os
import sqlite3
import time
import uuid
from contextlib import contextmanager
from dataclasses import dataclass
from pathlib import Path

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

PRODUCT_ID = "miucam_lifetime_unlock_try_300"
MAX_TOKEN_BYTES = 12 * 1024
CLAIMS = frozenset(("aud", "version", "productId", "entitlementId", "source",
                    "transactionFingerprint", "issuedAtMs", "status"))


def b64(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode("ascii").rstrip("=")


def unb64(value: str) -> bytes:
    if not value or "=" in value:
        raise ValueError("Non-canonical base64url")
    result = base64.b64decode(value + "=" * (-len(value) % 4), altchars=b"-_", validate=True)
    if b64(result) != value:
        raise ValueError("Non-canonical base64url")
    return result


def fingerprint(source: str, application: str, product: str, reference: str) -> str:
    return hashlib.sha256("\0".join((source, application, product, reference)).encode()).hexdigest()


@dataclass(frozen=True)
class StorePurchase:
    source: str
    reference: str
    fingerprint: str
    status: str
    acknowledged: bool = True


class LicenseSigner:
    def __init__(self, private_key: Ed25519PrivateKey, product_id: str = PRODUCT_ID):
        self.private_key = private_key
        self.product_id = product_id

    @classmethod
    def from_file(cls, filename: str, product_id: str = PRODUCT_ID):
        key = serialization.load_pem_private_key(Path(filename).read_bytes(), password=None)
        if not isinstance(key, Ed25519PrivateKey):
            raise ValueError("License signing key must be Ed25519")
        return cls(key, product_id)

    @property
    def public_key(self) -> str:
        return b64(self.private_key.public_key().public_bytes_raw())

    def sign(self, record: dict) -> str:
        payload = {
            "aud": "miucam", "version": 1, "productId": self.product_id,
            "entitlementId": record["entitlement_id"], "source": record["source"],
            "transactionFingerprint": record["fingerprint"],
            "issuedAtMs": record["issued_at_ms"], "status": record["status"],
        }
        header = b64(b'{"alg":"EdDSA","typ":"JWT"}')
        body = b64(json.dumps(payload, separators=(",", ":"), sort_keys=True).encode())
        signing_input = f"{header}.{body}".encode("ascii")
        return f"{header}.{body}.{b64(self.private_key.sign(signing_input))}"

    def verify(self, token: str) -> dict:
        if not isinstance(token, str) or len(token) > MAX_TOKEN_BYTES:
            raise ValueError("Invalid license token")
        try:
            header, body, signature = token.split(".")
            if json.loads(unb64(header)) != {"alg": "EdDSA", "typ": "JWT"}:
                raise ValueError("Invalid license header")
            self.private_key.public_key().verify(unb64(signature), f"{header}.{body}".encode("ascii"))
            claims = json.loads(unb64(body))
            if not isinstance(claims, dict) or set(claims) != CLAIMS:
                raise ValueError("Invalid license claims")
            if (claims["aud"] != "miucam" or type(claims["version"]) is not int
                    or claims["version"] != 1 or claims["productId"] != self.product_id
                    or claims["source"] not in ("google_play", "app_store")
                    or claims["status"] not in ("active", "revoked")
                    or type(claims["issuedAtMs"]) is not int
                    or not 0 < claims["issuedAtMs"] <= 9007199254740991
                    or not isinstance(claims["entitlementId"], str)
                    or not 1 <= len(claims["entitlementId"]) <= 256
                    or not isinstance(claims["transactionFingerprint"], str)
                    or len(claims["transactionFingerprint"]) != 64
                    or any(c not in "0123456789abcdef" for c in claims["transactionFingerprint"])):
                raise ValueError("Invalid license claims")
            return claims
        except (ValueError, TypeError, KeyError, UnicodeError, InvalidSignature) as error:
            raise ValueError("Invalid license token") from error


class LicenseRepository:
    """One atomic, durable record per store transaction, including ack recovery.

    Store tokens remain in this private database; API responses and application
    logs never expose them. Back up this database together with the signing key.
    """

    def __init__(self, path: str | Path, clock_ms=None):
        self.path = str(path)
        self.clock_ms = clock_ms or (lambda: time.time_ns() // 1_000_000)
        Path(path).parent.mkdir(parents=True, exist_ok=True)
        fd = os.open(self.path, os.O_CREAT | os.O_RDWR, 0o600)
        os.close(fd)
        os.chmod(self.path, 0o600)
        with self.connection() as db:
            db.execute("PRAGMA journal_mode=WAL")
            db.execute("""CREATE TABLE IF NOT EXISTS licenses (
                fingerprint TEXT PRIMARY KEY, entitlement_id TEXT NOT NULL UNIQUE,
                source TEXT NOT NULL, reference TEXT NOT NULL, status TEXT NOT NULL,
                issued_at_ms INTEGER NOT NULL, checked_at_ms INTEGER NOT NULL,
                ack_pending INTEGER NOT NULL, UNIQUE(source, reference))""")
            db.execute("CREATE INDEX IF NOT EXISTS pending_ack ON licenses(ack_pending, checked_at_ms)")

    @contextmanager
    def connection(self):
        db = sqlite3.connect(self.path, timeout=5, isolation_level=None)
        db.row_factory = sqlite3.Row
        db.execute("PRAGMA synchronous=FULL")
        try:
            yield db
        finally:
            db.close()

    def save(self, purchase: StorePurchase) -> dict:
        if purchase.status not in ("active", "revoked"):
            raise ValueError("Only confirmed store states may be persisted")
        with self.connection() as db:
            db.execute("BEGIN IMMEDIATE")
            previous = db.execute("SELECT * FROM licenses WHERE fingerprint=?", (purchase.fingerprint,)).fetchone()
            now = self.clock_ms()
            # A later result always has a newer revision, even in the same ms or
            # after the server clock moves backwards. Room devices reject replay.
            issued = max(now, previous["issued_at_ms"] + 1 if previous else 1)
            entitlement = previous["entitlement_id"] if previous else f"family_{uuid.uuid4().hex}"
            db.execute("""INSERT INTO licenses VALUES(?,?,?,?,?,?,?,?)
                ON CONFLICT(fingerprint) DO UPDATE SET status=excluded.status,
                issued_at_ms=excluded.issued_at_ms, checked_at_ms=excluded.checked_at_ms,
                ack_pending=excluded.ack_pending""", (
                purchase.fingerprint, entitlement, purchase.source, purchase.reference,
                purchase.status, issued, now,
                int(purchase.source == "google_play" and purchase.status == "active" and not purchase.acknowledged),
            ))
            db.execute("COMMIT")
            return dict(db.execute("SELECT * FROM licenses WHERE fingerprint=?", (purchase.fingerprint,)).fetchone())

    def get(self, entitlement_id: str) -> dict | None:
        with self.connection() as db:
            row = db.execute("SELECT * FROM licenses WHERE entitlement_id=?", (entitlement_id,)).fetchone()
            return dict(row) if row else None

    def find(self, source: str, reference: str) -> dict | None:
        with self.connection() as db:
            row = db.execute("SELECT * FROM licenses WHERE source=? AND reference=?", (source, reference)).fetchone()
            return dict(row) if row else None

    def pending_acknowledgements(self, limit: int = 20) -> list[dict]:
        with self.connection() as db:
            rows = db.execute("SELECT * FROM licenses WHERE ack_pending=1 AND checked_at_ms<? ORDER BY checked_at_ms LIMIT ?",
                              (self.clock_ms() - 30_000, limit)).fetchall()
            return [dict(row) for row in rows]

    def defer_acknowledgement(self, transaction_fingerprint: str):
        # Rotate a failed batch behind older pending work without changing the
        # entitlement or signed revision. Persist this across worker restarts.
        with self.connection() as db:
            db.execute("UPDATE licenses SET checked_at_ms=? WHERE fingerprint=? AND ack_pending=1",
                       (self.clock_ms(), transaction_fingerprint))
