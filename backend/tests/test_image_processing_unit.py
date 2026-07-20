"""Unit tests for bounded image processing (no Postgres)."""

from __future__ import annotations

from io import BytesIO

import pytest
from PIL import Image

from app.core.errors import AppError
from app.media.processing import process_upload_image


def _make_jpeg(width: int = 100, height: int = 80) -> bytes:
    buf = BytesIO()
    Image.new("RGB", (width, height), color=(200, 100, 50)).save(buf, format="JPEG")
    return buf.getvalue()


def test_process_upload_image_accepts_valid_jpeg() -> None:
    data = _make_jpeg(120, 90)
    processed = process_upload_image(data=data, declared_content_type="image/jpeg")
    assert processed.width == 120
    assert processed.height == 90
    assert processed.content_type == "image/jpeg"
    assert processed.display_content_type == "image/jpeg"
    assert processed.thumbnail_content_type == "image/jpeg"
    assert len(processed.display_bytes) > 0
    assert len(processed.thumbnail_bytes) > 0
    with Image.open(BytesIO(processed.display_bytes)) as display:
        assert display.format == "JPEG"
        assert display.size[0] <= 2048
        assert display.size[1] <= 2048
    with Image.open(BytesIO(processed.thumbnail_bytes)) as thumb:
        assert thumb.format == "JPEG"
        assert max(thumb.size) <= 512


def test_derivatives_strip_exif_while_original_bytes_unchanged() -> None:
    buf = BytesIO()
    image = Image.new("RGB", (80, 60), color=(10, 20, 30))
    exif = image.getexif()
    exif[271] = "DailySketchCamera"  # Make
    image.save(buf, format="JPEG", exif=exif)
    original = buf.getvalue()
    assert b"DailySketchCamera" in original

    processed = process_upload_image(data=original, declared_content_type="image/jpeg")
    assert b"DailySketchCamera" not in processed.display_bytes
    assert b"DailySketchCamera" not in processed.thumbnail_bytes
    # Callers retain original bytes verbatim; processing only returns derivatives.
    assert original == buf.getvalue()


def test_process_upload_image_rejects_corrupt_bytes() -> None:
    with pytest.raises(AppError) as exc_info:
        process_upload_image(data=b"not-an-image", declared_content_type="image/jpeg")
    assert exc_info.value.code == "invalid_image"
    assert exc_info.value.status_code == 422


def test_process_upload_image_produces_display_and_thumbnail_bytes() -> None:
    data = _make_jpeg(800, 600)
    processed = process_upload_image(data=data, declared_content_type="image/jpeg")
    assert processed.display_bytes != processed.thumbnail_bytes
    assert processed.display_bytes.startswith(b"\xff\xd8")
    assert processed.thumbnail_bytes.startswith(b"\xff\xd8")
