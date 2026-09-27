from __future__ import annotations

import asyncio
import base64
import json
import logging
import os
import time
from collections import OrderedDict
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from starlette.concurrency import run_in_threadpool

from .domain import StoreAdapter, StoreFailure, StoreFailureReason
from .licenses import LicenseRepository, LicenseSigner, PRODUCT_ID
from .service import BillingService
from .stores import AppStore, GooglePlayStore, StoreConfig

MAX_REQUEST_BYTES = 128 * 1024
REQUEST_BODY_TIMEOUT_SECONDS = 10


def configured_service() -> BillingService:
    key_file = os.environ["MIUCAM_LICENSE_PRIVATE_KEY_FILE"]
    signer = LicenseSigner.from_file(key_file)
    repository = LicenseRepository(os.environ.get("MIUCAM_LICENSE_DATABASE", "/data/licenses.sqlite3"))
    stores: dict[str, StoreAdapter] = {}
    environment = os.environ.get("MIUCAM_STORE_ENVIRONMENT", "production")
    if environment not in ("production", "sandbox"):
        raise ValueError("MIUCAM_STORE_ENVIRONMENT must be production or sandbox")
    config = StoreConfig(allow_test_purchases=environment == "sandbox")
    if os.environ.get("MIUCAM_GOOGLE_PLAY_ENABLED") == "true":
        stores["google_play"] = GooglePlayStore(config)
    if os.environ.get("MIUCAM_APP_STORE_ENABLED") == "true":
        apple_id = os.environ.get("MIUCAM_APPLE_APP_ID")
        stores["app_store"] = AppStore.configured(
            config, signing_key_path=os.environ["MIUCAM_APPLE_SIGNING_KEY_FILE"],
            key_id=os.environ["MIUCAM_APPLE_KEY_ID"], issuer_id=os.environ["MIUCAM_APPLE_ISSUER_ID"],
            root_certificate_paths=os.environ["MIUCAM_APPLE_ROOT_CERTIFICATES"].split(os.pathsep),
            app_apple_id=int(apple_id) if apple_id else None, environment=environment,
        )
    if not stores:
        raise ValueError("At least one real store verifier must be configured")
    return BillingService(repository, signer, stores, store_environment=environment)


class BodyLimitMiddleware:
    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http":
            return await self.app(scope, receive, send)
        body = bytearray()
        too_large = False
        try:
            # One deadline for the whole body: periodic tiny chunks must not
            # keep a request alive indefinitely. Buffer bytes rather than an
            # unbounded number of empty/tiny ASGI message objects.
            async with asyncio.timeout(REQUEST_BODY_TIMEOUT_SECONDS):
                while True:
                    message = await receive()
                    if message["type"] == "http.disconnect":
                        return
                    chunk = message.get("body", b"")
                    if len(body) + len(chunk) > MAX_REQUEST_BYTES:
                        too_large = True
                        break
                    body.extend(chunk)
                    if not message.get("more_body", False):
                        break
        except TimeoutError:
            return await JSONResponse({"verified": False, "reasonCode": "transient"}, status_code=408)(scope, receive, send)
        if too_large:
            return await JSONResponse({"verified": False, "reasonCode": "rejected"}, status_code=413)(scope, receive, send)
        replayed = False
        async def replay():
            nonlocal replayed
            if replayed:
                return await receive()
            replayed = True
            return {"type": "http.request", "body": bytes(body), "more_body": False}
        await self.app(scope, replay, send)


def create_app(service: BillingService | None = None, *, run_recovery: bool = True,
               google_notification_auth=None) -> FastAPI:
    @asynccontextmanager
    async def lifespan(app):
        app.state.billing = service or configured_service()
        stop = asyncio.Event()
        async def recover():
            while not stop.is_set():
                try:
                    await run_in_threadpool(app.state.billing.recover_acknowledgements)
                except Exception:
                    logging.getLogger(__name__).warning("Billing recovery deferred; durable work retained")
                try:
                    await asyncio.wait_for(stop.wait(), timeout=30)
                except TimeoutError:
                    pass
        task = asyncio.create_task(recover()) if run_recovery else None
        try:
            yield
        finally:
            stop.set()
            if task:
                await task

    app = FastAPI(lifespan=lifespan, docs_url=None, redoc_url=None, openapi_url=None)
    app.add_middleware(BodyLimitMiddleware)
    attempts = OrderedDict()

    @app.middleware("http")
    async def headers_and_rate(request, call_next):
        if request.url.path == "/verify":
            # Bounded in-memory protection; deployments should also rate-limit
            # at the HTTPS proxy. Trust forwarded IPs only from that proxy.
            client = request.client.host if request.client else "unknown"
            now = time.monotonic()
            start, count = attempts.pop(client, (now, 0))
            if now - start > 60:
                start, count = now, 0
            attempts[client] = (start, count + 1)
            while len(attempts) > 2048:
                attempts.popitem(last=False)
            if count >= 120:
                return JSONResponse({"verified": False, "reasonCode": "transient"}, status_code=429,
                                    headers={"Retry-After": "60", "Cache-Control": "no-store"})
        response = await call_next(request)
        response.headers["Cache-Control"] = "no-store"
        response.headers["X-Content-Type-Options"] = "nosniff"
        return response

    @app.exception_handler(StoreFailure)
    async def store_failure(_, error):
        status = 503 if error.reason in (StoreFailureReason.TRANSIENT, StoreFailureReason.CONFIGURATION) else 200
        return JSONResponse({"verified": False, "reasonCode": error.reason,
                             "reason": "Purchase verification is unavailable." if status == 503 else "The store did not verify this purchase."},
                            status_code=status)

    async def read_body(request):
        if request.headers.get("content-type", "").split(";", 1)[0].strip() != "application/json":
            raise StoreFailure("rejected")
        try:
            body = await request.json()
            if not isinstance(body, dict):
                raise ValueError()
            return body
        except (ValueError, UnicodeError):
            raise StoreFailure("rejected") from None

    @app.get("/health")
    async def health(request: Request):
        billing = request.app.state.billing
        result = {"ok": True, "sources": billing.available_sources, "productId": billing.product_id}
        if billing.store_environment is not None:
            result["storeEnvironment"] = billing.store_environment
        return result

    @app.post("/verify")
    async def verify(request: Request):
        body = await read_body(request)
        try:
            return await run_in_threadpool(request.app.state.billing.verify, body)
        except ValueError:
            raise StoreFailure("rejected") from None

    @app.post("/notifications/apple")
    async def apple_notification(request: Request):
        body = await read_body(request)
        payload = body.get("signedPayload")
        if not isinstance(payload, str):
            raise StoreFailure("rejected")
        await run_in_threadpool(request.app.state.billing.process_apple_notification, payload)
        return {"ok": True}

    @app.post("/notifications/google")
    async def google_notification(request: Request):
        auth = google_notification_auth or _verify_google_notification_authorization
        try:
            await run_in_threadpool(auth, request.headers.get("authorization", ""))
        except Exception:
            return JSONResponse({"ok": False}, status_code=401)
        body = await read_body(request)
        try:
            data = json.loads(base64.b64decode(body["message"]["data"], validate=True))
            if not isinstance(data, dict) or data.get("packageName") != "com.miucam.app":
                raise ValueError()
            notice = data.get("oneTimeProductNotification") or data.get("voidedPurchaseNotification")
            if notice:
                if not isinstance(notice, dict):
                    raise ValueError()
                if notice.get("sku", PRODUCT_ID) != PRODUCT_ID:
                    return {"ok": True}
                token = notice["purchaseToken"]
                if not isinstance(token, str) or not 1 <= len(token) <= 8192:
                    raise ValueError()
            else:
                return {"ok": True}
        except (KeyError, TypeError, ValueError, UnicodeError):
            return JSONResponse({"ok": False}, status_code=400)
        await run_in_threadpool(request.app.state.billing.reconcile, "google_play", token)
        return {"ok": True}

    return app


def _verify_google_notification_authorization(authorization: str):
    from google.auth.transport.requests import Request
    from google.oauth2.id_token import verify_oauth2_token
    if not authorization.startswith("Bearer "):
        raise ValueError("Missing notification authorization")
    audience = os.environ["MIUCAM_GOOGLE_NOTIFICATION_AUDIENCE"]
    email = os.environ["MIUCAM_GOOGLE_NOTIFICATION_EMAIL"]
    class BoundedRequest(Request):
        def __call__(self, *args, **kwargs):
            kwargs["timeout"] = 8
            return super().__call__(*args, **kwargs)
    claims = verify_oauth2_token(authorization[7:], BoundedRequest(), audience=audience)
    if claims.get("email") != email or claims.get("email_verified") is not True:
        raise ValueError("Wrong notification sender")
