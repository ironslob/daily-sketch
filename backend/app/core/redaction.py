"""Log and string redaction helpers."""

from __future__ import annotations

import re
from typing import Any

_REDACTED = "[REDACTED]"

_SENSITIVE_KEY_PATTERN = re.compile(
    r"(authorization|password|secret|token|cookie|jwt|bearer|credential|api[_-]?key|"
    r"signed[_-]?url|x-moderation-token)",
    re.IGNORECASE,
)

_SIGNED_URL_PATTERN = re.compile(
    r"(https?://[^\s\"']+[?&](?:X-Amz-Signature|Signature|token)=[^\s\"'&]+)",
    re.IGNORECASE,
)

_EMAIL_PATTERN = re.compile(r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b")


def redact_string(value: str) -> str:
    """Redact sensitive substrings from a log message or field value."""
    if not value:
        return value
    redacted = _SIGNED_URL_PATTERN.sub(_REDACTED, value)
    redacted = _EMAIL_PATTERN.sub(_REDACTED, redacted)
    if redacted.lower().startswith("bearer "):
        return f"Bearer {_REDACTED}"
    return redacted


def redact_value(value: Any) -> Any:
    """Recursively redact sensitive values in dict/list structures."""
    if isinstance(value, str):
        return redact_string(value)
    if isinstance(value, dict):
        result: dict[Any, Any] = {}
        for key, item in value.items():
            key_str = str(key)
            if _SENSITIVE_KEY_PATTERN.search(key_str):
                result[key] = _REDACTED
            elif key_str.lower() in {"caption", "body", "reflection", "draft", "email"}:
                result[key] = _REDACTED
            else:
                result[key] = redact_value(item)
        return result
    if isinstance(value, list):
        return [redact_value(item) for item in value]
    return value
