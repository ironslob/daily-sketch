"""MinIO / S3-compatible storage adapter."""

from __future__ import annotations

import asyncio
from datetime import UTC, datetime
from functools import partial
from typing import Any
from uuid import uuid4

import boto3
from botocore.client import Config
from botocore.exceptions import ClientError

from app.core.errors import AppError
from app.core.settings import Settings
from app.storage.base import ObjectMetadata, SignedUpload


class MinioStorageAdapter:
    """Signed upload/read and object operations against S3-compatible storage."""

    def __init__(self, settings: Settings) -> None:
        self._settings = settings
        self._bucket = settings.storage_bucket
        self._client: Any = self._build_client(settings.storage_endpoint)
        self._public_client: Any = (
            self._build_client(settings.resolved_storage_public_endpoint)
            if settings.resolved_storage_public_endpoint != settings.storage_endpoint
            else self._client
        )

    def _build_client(self, endpoint: str) -> Any:
        return boto3.client(
            "s3",
            endpoint_url=endpoint,
            aws_access_key_id=self._settings.storage_access_key,
            aws_secret_access_key=self._settings.storage_secret_key,
            region_name=self._settings.storage_region,
            use_ssl=self._settings.storage_use_ssl,
            config=Config(signature_version="s3v4", s3={"addressing_style": "path"}),
        )

    async def create_signed_upload(
        self,
        *,
        key: str,
        content_type: str,
        max_bytes: int,
        expires_at: datetime,
    ) -> SignedUpload:
        expires_in = max(int((expires_at - datetime.now(UTC)).total_seconds()), 60)
        url = await asyncio.to_thread(
            partial(
                self._public_client.generate_presigned_url,
                "put_object",
                Params={
                    "Bucket": self._bucket,
                    "Key": key,
                    "ContentType": content_type,
                },
                ExpiresIn=expires_in,
                HttpMethod="PUT",
            )
        )
        return SignedUpload(
            upload_id=uuid4(),
            url=url,
            method="PUT",
            headers={"Content-Type": content_type},
            expires_at=expires_at,
            max_bytes=max_bytes,
            content_type=content_type,
        )

    async def verify_object(self, *, key: str) -> ObjectMetadata:
        try:
            response: dict[str, Any] = await asyncio.to_thread(
                partial(self._client.head_object, Bucket=self._bucket, Key=key)
            )
        except ClientError as exc:
            code = exc.response.get("Error", {}).get("Code", "")
            if code in {"404", "NoSuchKey", "NotFound"}:
                raise AppError(
                    code="object_missing",
                    message="The uploaded image could not be found. Please try again.",
                    status_code=422,
                ) from exc
            raise
        content_type = response.get("ContentType") or "application/octet-stream"
        byte_size = int(response.get("ContentLength") or 0)
        etag = response.get("ETag")
        if isinstance(etag, str):
            etag = etag.strip('"')
        return ObjectMetadata(
            key=key,
            content_type=content_type,
            byte_size=byte_size,
            etag=etag,
        )

    async def read_url(self, *, key: str, expires_at: datetime) -> str:
        expires_in = max(int((expires_at - datetime.now(UTC)).total_seconds()), 60)
        return await asyncio.to_thread(
            partial(
                self._public_client.generate_presigned_url,
                "get_object",
                Params={"Bucket": self._bucket, "Key": key},
                ExpiresIn=expires_in,
                HttpMethod="GET",
            )
        )

    async def delete_object(self, *, key: str) -> None:
        await asyncio.to_thread(partial(self._client.delete_object, Bucket=self._bucket, Key=key))

    async def download_object(self, *, key: str) -> bytes:
        try:
            response = await asyncio.to_thread(
                partial(self._client.get_object, Bucket=self._bucket, Key=key)
            )
        except ClientError as exc:
            code = exc.response.get("Error", {}).get("Code", "")
            if code in {"404", "NoSuchKey", "NotFound"}:
                raise AppError(
                    code="object_missing",
                    message="The uploaded image could not be found. Please try again.",
                    status_code=422,
                ) from exc
            raise
        body = response["Body"]
        return await asyncio.to_thread(body.read)

    async def ping(self) -> bool:
        try:
            await asyncio.to_thread(partial(self._client.head_bucket, Bucket=self._bucket))
        except ClientError:
            return False
        return True

    async def put_object(
        self,
        *,
        key: str,
        body: bytes,
        content_type: str,
    ) -> ObjectMetadata:
        await asyncio.to_thread(
            partial(
                self._client.put_object,
                Bucket=self._bucket,
                Key=key,
                Body=body,
                ContentType=content_type,
            )
        )
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
