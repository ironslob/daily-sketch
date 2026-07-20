"""Prometheus metrics and OpenTelemetry tracing setup."""

from __future__ import annotations

import logging
import time
from collections import defaultdict
from typing import Any

from starlette.responses import PlainTextResponse, Response
from starlette.types import ASGIApp, Message, Receive, Scope, Send

from app.core.settings import Settings

logger = logging.getLogger(__name__)

_count_by_route: dict[str, int] = defaultdict(int)
_latency_ms_by_route: dict[str, list[float]] = defaultdict(list)
_auth_failures = 0
_job_outcomes: dict[str, int] = defaultdict(int)


def record_auth_failure() -> None:
    global _auth_failures
    _auth_failures += 1


def record_job_outcome(job_name: str, *, success: bool) -> None:
    _job_outcomes[f"{job_name}:{'ok' if success else 'error'}"] += 1


def _route_key(scope: Scope) -> str:
    method = scope.get("method", "GET")
    path = scope.get("path", "")
    if path.startswith("/api/v1/prompts"):
        return f"{method} prompts"
    if path.startswith("/api/v1/feed"):
        return f"{method} feed"
    if path.startswith("/api/v1/users") and path.endswith("/submissions"):
        return f"{method} profile_submissions"
    if path.endswith("/like"):
        return f"{method} like"
    if path.endswith("/reflections"):
        return f"{method} reflection"
    if path.startswith("/api/v1/uploads"):
        return f"{method} upload"
    if path.startswith("/api/v1/submissions"):
        return f"{method} submission"
    if path == "/api/v1/me" and method == "DELETE":
        return f"{method} account_deletion"
    return f"{method} {path}"


class MetricsMiddleware:
    """Collect request counts and latencies for /metrics export."""

    def __init__(self, app: ASGIApp, settings: Settings) -> None:
        self.app = app
        self._settings = settings

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http" or not self._settings.metrics_enabled:
            await self.app(scope, receive, send)
            return

        started = time.perf_counter()
        status_code = 500

        async def send_wrapper(message: Message) -> None:
            nonlocal status_code
            if message["type"] == "http.response.start":
                status_code = int(message["status"])
            await send(message)

        await self.app(scope, receive, send_wrapper)
        route = _route_key(scope)
        latency_ms = (time.perf_counter() - started) * 1000
        _count_by_route[route] += 1
        bucket = _latency_ms_by_route[route]
        bucket.append(latency_ms)
        if len(bucket) > 500:
            del bucket[: len(bucket) - 500]


def metrics_response() -> Response:
    lines: list[str] = []
    lines.append("# HELP dailysketch_http_requests_total Total HTTP requests by route class")
    lines.append("# TYPE dailysketch_http_requests_total counter")
    for route, count in sorted(_count_by_route.items()):
        label = route.replace('"', "")
        lines.append(f'dailysketch_http_requests_total{{route="{label}"}} {count}')

    lines.append("# HELP dailysketch_auth_failures_total Authentication failures")
    lines.append("# TYPE dailysketch_auth_failures_total counter")
    lines.append(f"dailysketch_auth_failures_total {_auth_failures}")

    lines.append("# HELP dailysketch_job_outcomes_total Scheduled job outcomes")
    lines.append("# TYPE dailysketch_job_outcomes_total counter")
    for key, count in sorted(_job_outcomes.items()):
        label = key.replace('"', "")
        lines.append(f'dailysketch_job_outcomes_total{{job="{label}"}} {count}')

    lines.append("# HELP dailysketch_http_latency_ms_p95 Approximate p95 latency by route class")
    lines.append("# TYPE dailysketch_http_latency_ms_p95 gauge")
    for route, samples in sorted(_latency_ms_by_route.items()):
        if not samples:
            continue
        ordered = sorted(samples)
        idx = max(int(len(ordered) * 0.95) - 1, 0)
        p95 = ordered[idx]
        label = route.replace('"', "")
        lines.append(f'dailysketch_http_latency_ms_p95{{route="{label}"}} {p95:.2f}')

    return PlainTextResponse("\n".join(lines) + "\n", media_type="text/plain; version=0.0.4")


_tracer: Any | None = None


def configure_observability(settings: Settings) -> None:
    """Initialize optional Sentry and OpenTelemetry exporters."""
    global _tracer

    if settings.sentry_dsn:
        try:
            import sentry_sdk

            sentry_sdk.init(
                dsn=settings.sentry_dsn,
                environment=settings.app_env,
                release=settings.release_version,
                traces_sample_rate=0.1 if settings.is_remote_environment else 0.0,
            )
        except Exception:
            logger.exception("sentry_init_failed")

    if settings.otel_exporter_otlp_endpoint:
        try:
            from opentelemetry import trace
            from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
            from opentelemetry.sdk.resources import Resource
            from opentelemetry.sdk.trace import TracerProvider
            from opentelemetry.sdk.trace.export import BatchSpanProcessor

            provider = TracerProvider(
                resource=Resource.create(
                    {
                        "service.name": "dailysketch-backend",
                        "deployment.environment": settings.app_env,
                        "service.version": settings.release_version,
                    }
                )
            )
            exporter = OTLPSpanExporter(endpoint=settings.otel_exporter_otlp_endpoint)
            provider.add_span_processor(BatchSpanProcessor(exporter))
            trace.set_tracer_provider(provider)
            _tracer = trace.get_tracer("dailysketch")
        except Exception:
            logger.exception("otel_init_failed")


def get_tracer() -> Any | None:
    return _tracer


async def send_alert(settings: Settings, *, title: str, detail: str) -> None:
    """Best-effort webhook alert delivery when configured."""
    if not settings.alert_webhook_url:
        return
    try:
        import httpx

        async with httpx.AsyncClient(timeout=5.0) as client:
            await client.post(
                settings.alert_webhook_url,
                json={"title": title, "detail": detail, "environment": settings.app_env},
            )
    except Exception:
        logger.exception("alert_delivery_failed", extra={"title": title})
