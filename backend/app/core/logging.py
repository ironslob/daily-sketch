"""Structured JSON logging configuration."""

from __future__ import annotations

import json
import logging
import sys
from datetime import UTC, datetime
from typing import Any

from app.core.redaction import redact_string, redact_value
from app.core.settings import Settings

_STRUCTURED_KEYS = (
    "request_id",
    "method",
    "route",
    "status",
    "latency_ms",
    "environment",
    "release_version",
    "error_code",
)


class JsonLogFormatter(logging.Formatter):
    """Emit one JSON object per log record."""

    def format(self, record: logging.LogRecord) -> str:
        payload: dict[str, Any] = {
            "timestamp": datetime.now(UTC).isoformat().replace("+00:00", "Z"),
            "level": record.levelname,
            "logger": record.name,
            "message": redact_string(record.getMessage()),
        }
        for key in _STRUCTURED_KEYS:
            value = getattr(record, key, None)
            if value is not None and value != "":
                payload[key] = redact_value(value)
        if record.exc_info:
            payload["exception"] = redact_string(self.formatException(record.exc_info))
        return json.dumps(payload, default=str)


def configure_logging(settings: Settings) -> None:
    """Configure root logging for structured JSON output."""
    root = logging.getLogger()
    root.handlers.clear()
    root.setLevel(settings.log_level.upper())

    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JsonLogFormatter())
    root.addHandler(handler)

    # Keep noisy third-party loggers quieter in local development.
    logging.getLogger("uvicorn.access").setLevel(logging.WARNING)
