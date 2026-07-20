"""In-process sliding-window rate limiting for abuse-prone endpoints."""

from __future__ import annotations

import asyncio
import time
from collections import defaultdict, deque
from dataclasses import dataclass
from typing import Literal

from starlette.types import ASGIApp, Receive, Scope, Send

from app.core.settings import Settings

RateLimitKind = Literal[
    "default",
    "upload",
    "report",
    "reflection",
    "username",
    "auth",
    "moderation",
    "like",
    "block",
    "deletion",
]


@dataclass(frozen=True, slots=True)
class RateLimitRule:
    kind: RateLimitKind
    max_requests: int


class InMemoryRateLimiter:
    """Thread-safe sliding window limiter keyed by client identifier."""

    def __init__(self, window_seconds: int) -> None:
        self._window_seconds = window_seconds
        self._buckets: dict[str, deque[float]] = defaultdict(deque)
        self._lock = asyncio.Lock()

    async def allow(self, key: str, *, max_requests: int) -> tuple[bool, int]:
        now = time.monotonic()
        cutoff = now - self._window_seconds
        async with self._lock:
            bucket = self._buckets[key]
            while bucket and bucket[0] <= cutoff:
                bucket.popleft()
            if len(bucket) >= max_requests:
                retry_after = max(int(self._window_seconds - (now - bucket[0])), 1)
                return False, retry_after
            bucket.append(now)
            return True, 0


def _client_key(scope: Scope) -> str:
    client = scope.get("client")
    if isinstance(client, tuple) and len(client) >= 1:
        host = client[0]
        return host if isinstance(host, str) else str(host)
    headers: dict[str, str] = {
        key.decode("latin-1").lower(): value.decode("latin-1")
        for key, value in scope.get("headers", [])
    }
    forwarded_raw = headers.get("x-forwarded-for", "")
    if forwarded_raw:
        first_hop = forwarded_raw.split(",", 1)[0]
        return first_hop.strip()
    return "unknown"


def _rate_limit_rule(method: str, path: str, settings: Settings) -> RateLimitRule | None:
    if path.startswith("/internal/moderation"):
        return RateLimitRule("moderation", settings.rate_limit_moderation_max)
    if path == "/api/v1/uploads" and method == "POST":
        return RateLimitRule("upload", settings.rate_limit_upload_max)
    if path == "/api/v1/reports" and method == "POST":
        return RateLimitRule("report", settings.rate_limit_report_max)
    if path.endswith("/reflections") and method == "POST":
        return RateLimitRule("reflection", settings.rate_limit_reflection_max)
    if path == "/api/v1/me" and method == "PATCH":
        return RateLimitRule("username", settings.rate_limit_username_max)
    if path.endswith("/like") and method == "PUT":
        return RateLimitRule("like", settings.rate_limit_default_max)
    if path.endswith("/block") and method == "PUT":
        return RateLimitRule("block", settings.rate_limit_default_max)
    if path == "/api/v1/me" and method == "DELETE":
        return RateLimitRule("deletion", settings.rate_limit_default_max)
    if path.startswith("/api/v1/") and method in {"POST", "PUT", "PATCH", "DELETE"}:
        return RateLimitRule("default", settings.rate_limit_default_max)
    return None


class RateLimitMiddleware:
    """Apply sliding-window limits to abuse-prone HTTP routes."""

    def __init__(self, app: ASGIApp, settings: Settings) -> None:
        self.app = app
        self._settings = settings
        self._limiter = InMemoryRateLimiter(settings.rate_limit_window_seconds)

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        method = scope.get("method", "GET")
        path = scope.get("path", "")
        rule = _rate_limit_rule(method, path, self._settings)
        if rule is None:
            await self.app(scope, receive, send)
            return

        client = _client_key(scope)
        bucket_key = f"{rule.kind}:{client}"
        allowed, retry_after = await self._limiter.allow(
            bucket_key,
            max_requests=rule.max_requests,
        )
        if not allowed:
            body = b'{"error":{"code":"rate_limited","message":"Too many requests. Please try again later.","details":{},"request_id":"00000000-0000-0000-0000-000000000000"}}'
            await send(
                {
                    "type": "http.response.start",
                    "status": 429,
                    "headers": [
                        (b"content-type", b"application/json"),
                        (b"content-length", str(len(body)).encode()),
                        (b"retry-after", str(retry_after).encode()),
                    ],
                }
            )
            await send({"type": "http.response.body", "body": body, "more_body": False})
            return

        await self.app(scope, receive, send)
