import asyncio

from miucam_billing import app as billing_app


def test_slow_trickle_cannot_renew_the_request_body_deadline(monkeypatch):
    monkeypatch.setattr(billing_app, "REQUEST_BODY_TIMEOUT_SECONDS", 0.03, raising=False)
    forwarded = []
    responses = []

    async def run():
        chunks_read = 0

        async def receive():
            nonlocal chunks_read
            await asyncio.sleep(0.01)
            chunks_read += 1
            return {"type": "http.request", "body": b" ", "more_body": chunks_read < 10}

        async def send(message):
            responses.append(message)

        async def downstream(scope, receive, send):
            forwarded.append(True)

        await asyncio.wait_for(
            billing_app.BodyLimitMiddleware(downstream)({"type": "http"}, receive, send),
            timeout=1,
        )
        assert chunks_read < 10

    asyncio.run(run())
    assert not forwarded
    assert responses[0]["status"] == 408


def test_fragmented_body_is_preserved_and_disconnect_is_still_observable():
    async def run():
        messages = iter([
            {"type": "http.request", "body": b'{"value":', "more_body": True},
            {"type": "http.request", "body": b"", "more_body": True},
            {"type": "http.request", "body": b'"ok"}', "more_body": False},
            {"type": "http.disconnect"},
        ])
        received_body = bytearray()

        async def receive():
            return next(messages)

        async def downstream(scope, receive, send):
            while True:
                message = await receive()
                received_body.extend(message["body"])
                if not message.get("more_body", False):
                    break
            assert await receive() == {"type": "http.disconnect"}

        await billing_app.BodyLimitMiddleware(downstream)({"type": "http"}, receive, None)
        assert received_body == b'{"value":"ok"}'

    asyncio.run(run())


def test_disconnect_before_body_completion_does_not_reach_billing():
    async def run():
        messages = iter([
            {"type": "http.request", "body": b"{", "more_body": True},
            {"type": "http.disconnect"},
        ])

        async def receive():
            return next(messages)

        async def downstream(scope, receive, send):
            raise AssertionError("Incomplete request reached billing")

        await billing_app.BodyLimitMiddleware(downstream)({"type": "http"}, receive, None)

    asyncio.run(run())
