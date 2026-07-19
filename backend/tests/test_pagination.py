"""Unit tests for opaque cursor encode/decode."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime

import pytest

from app.core.errors import AppError
from app.core.pagination import decode_cursor, encode_cursor


def test_encode_decode_round_trip() -> None:
    published_at = datetime(2026, 7, 18, 20, 12, 0, tzinfo=UTC)
    submission_id = uuid.UUID("d4e5f6a7-b8c9-0123-def0-234567890123")

    cursor = encode_cursor(published_at=published_at, submission_id=submission_id)
    decoded_at, decoded_id = decode_cursor(cursor)

    assert decoded_at == published_at
    assert decoded_id == submission_id


def test_decode_rejects_malformed_cursor() -> None:
    with pytest.raises(AppError) as exc_info:
        decode_cursor("not-a-valid-cursor")
    assert exc_info.value.code == "invalid_cursor"
    assert exc_info.value.status_code == 422


def test_decode_rejects_missing_separator() -> None:
    import base64

    payload = base64.urlsafe_b64encode(b"2026-07-18T20:12:00+00:00").decode("ascii")
    with pytest.raises(AppError) as exc_info:
        decode_cursor(payload)
    assert exc_info.value.code == "invalid_cursor"


def test_decode_rejects_naive_timestamp() -> None:
    import base64

    payload = base64.urlsafe_b64encode(
        b"2026-07-18T20:12:00|d4e5f6a7-b8c9-0123-def0-234567890123"
    ).decode("ascii")
    with pytest.raises(AppError) as exc_info:
        decode_cursor(payload)
    assert exc_info.value.code == "invalid_cursor"


def test_encode_rejects_naive_timestamp() -> None:
    with pytest.raises(ValueError):
        encode_cursor(
            published_at=datetime(2026, 7, 18, 20, 12, 0),
            submission_id=uuid.uuid4(),
        )
