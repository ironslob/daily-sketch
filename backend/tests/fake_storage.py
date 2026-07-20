"""In-memory StorageAdapter for upload and submission tests."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from uuid import uuid4

from app.core.errors import AppError
from app.storage.base import ObjectMetadata, SignedUpload


@dataclass
class _StoredObject:
    body: bytes
    content_type: str


class InMemoryStorageAdapter:
    """Dict-backed storage adapter implementing the full StorageAdapter protocol."""

    def __init__(self) -> None:
        self._objects: dict[str, _StoredObject] = {}

    def put_bytes(self, key: str, data: bytes, content_type: str) -> None:
        """Test helper to simulate a client PUT to a signed upload URL."""
        self._objects[key] = _StoredObject(body=data, content_type=content_type)

    async def create_signed_upload(
        self,
        *,
        key: str,
        content_type: str,
        max_bytes: int,
        expires_at: datetime,
    ) -> SignedUpload:
        return SignedUpload(
            upload_id=uuid4(),
            url=f"https://storage.test/upload/{key}",
            method="PUT",
            headers={"Content-Type": content_type},
            expires_at=expires_at,
            max_bytes=max_bytes,
            content_type=content_type,
        )

    async def verify_object(self, *, key: str) -> ObjectMetadata:
        stored = self._objects.get(key)
        if stored is None:
            raise AppError(
                code="object_missing",
                message="The uploaded image could not be found. Please try again.",
                status_code=422,
            )
        return ObjectMetadata(
            key=key,
            content_type=stored.content_type,
            byte_size=len(stored.body),
        )

    async def read_url(self, *, key: str, expires_at: datetime) -> str:
        del expires_at
        return f"https://storage.test/read/{key}"

    async def delete_object(self, *, key: str) -> None:
        self._objects.pop(key, None)

    async def download_object(self, *, key: str) -> bytes:
        stored = self._objects.get(key)
        if stored is None:
            raise AppError(
                code="object_missing",
                message="The uploaded image could not be found. Please try again.",
                status_code=422,
            )
        return stored.body

    async def put_object(
        self,
        *,
        key: str,
        body: bytes,
        content_type: str,
    ) -> ObjectMetadata:
        self._objects[key] = _StoredObject(body=body, content_type=content_type)
        return ObjectMetadata(
            key=key,
            content_type=content_type,
            byte_size=len(body),
        )

    def derivative_key(self, *, original_key: str, kind: str) -> str:
        if original_key.endswith("/original"):
            prefix = original_key[: -len("/original")]
            return f"{prefix}/{kind}"
        return f"{original_key}/{kind}"

    async def ping(self) -> bool:
        return True

    def has_object(self, key: str) -> bool:
        return key in self._objects
