"""Request timeout and body-size enforcement middleware."""

from __future__ import annotations

import asyncio
import json

from starlette.types import ASGIApp, Receive, Scope, Send

from app.core.settings import Settings


def _request_id_from_scope(scope: Scope) -> str:
    headers: dict[str, str] = {
        key.decode("latin-1").lower(): value.decode("latin-1")
        for key, value in scope.get("headers", [])
    }
    request_id = headers.get("x-request-id", "").strip()
    if request_id:
        return request_id
    return "00000000-0000-0000-0000-000000000000"


class RequestSizeLimitMiddleware:
    """Reject requests whose Content-Length exceeds the configured maximum."""

    def __init__(self, app: ASGIApp, settings: Settings) -> None:
        self.app = app
        self._max_bytes = settings.max_request_body_bytes

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        headers = {
            key.decode("latin-1").lower(): value.decode("latin-1")
            for key, value in scope.get("headers", [])
        }
        content_length = headers.get("content-length")
        if content_length:
            try:
                length = int(content_length)
            except ValueError:
                length = 0
            if length > self._max_bytes:
                request_id = _request_id_from_scope(scope)
                payload = {
                    "error": {
                        "code": "payload_too_large",
                        "message": "Request body is too large.",
                        "details": {},
                        "request_id": request_id,
                    }
                }
                body = json.dumps(payload, separators=(",", ":")).encode()
                await send(
                    {
                        "type": "http.response.start",
                        "status": 413,
                        "headers": [
                            (b"content-type", b"application/json"),
                            (b"content-length", str(len(body)).encode()),
                            (b"x-request-id", request_id.encode()),
                        ],
                    }
                )
                await send({"type": "http.response.body", "body": body, "more_body": False})
                return

        await self.app(scope, receive, send)


class RequestTimeoutMiddleware:
    """Abort requests that exceed the configured wall-clock timeout."""

    def __init__(self, app: ASGIApp, settings: Settings) -> None:
        self.app = app
        self._timeout = settings.request_timeout_seconds

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        try:
            await asyncio.wait_for(self.app(scope, receive, send), timeout=self._timeout)
        except TimeoutError:
            request_id = _request_id_from_scope(scope)
            payload = {
                "error": {
                    "code": "request_timeout",
                    "message": "The request timed out.",
                    "details": {},
                    "request_id": request_id,
                }
            }
            body = json.dumps(payload, separators=(",", ":")).encode()
            await send(
                {
                    "type": "http.response.start",
                    "status": 504,
                    "headers": [
                        (b"content-type", b"application/json"),
                        (b"content-length", str(len(body)).encode()),
                        (b"x-request-id", request_id.encode()),
                    ],
                }
            )
            await send({"type": "http.response.body", "body": body, "more_body": False})
