"""Upload application service."""

from __future__ import annotations

import hashlib
import json
import uuid
from datetime import timedelta

from sqlalchemy.ext.asyncio import AsyncSession

from app.core.clock import Clock
from app.core.errors import AppError
from app.core.settings import Settings, get_settings
from app.media.processing import process_upload_image
from app.models.upload import Upload, UploadPurpose, UploadStatus
from app.models.user import User
from app.repositories.idempotency import IdempotencyRepository
from app.repositories.uploads import UploadRepository
from app.schemas.uploads import (
    CreateUploadRequest,
    SignedUploadResponse,
    UploadPurposeSchema,
    UploadResponse,
)
from app.storage.base import StorageAdapter

CREATE_ENDPOINT = "POST /api/v1/uploads"


class UploadService:
    def __init__(
        self,
        session: AsyncSession,
        clock: Clock,
        storage: StorageAdapter,
        settings: Settings | None = None,
    ) -> None:
        self._uploads = UploadRepository(session)
        self._idempotency = IdempotencyRepository(session)
        self._clock = clock
        self._storage = storage
        self._settings = settings or get_settings()

    async def create(
        self,
        *,
        user: User,
        payload: CreateUploadRequest,
        idempotency_key: str | None,
    ) -> tuple[UploadResponse, int]:
        request_hash = _hash_create_request(payload)
        if idempotency_key:
            existing = await self._idempotency.get(
                user_id=user.id,
                endpoint=CREATE_ENDPOINT,
                key=idempotency_key,
            )
            if existing is not None:
                if existing.request_hash != request_hash:
                    raise AppError(
                        code="idempotency_key_conflict",
                        message="This idempotency key was already used with a different request.",
                        status_code=409,
                    )
                return UploadResponse.model_validate(
                    existing.response_body
                ), existing.response_status

        self._validate_create_request(payload)
        now = self._clock.now()
        expires_at = now + timedelta(seconds=self._settings.signed_upload_expiry_seconds)
        upload_id = uuid.uuid4()
        storage_key = f"users/{user.id}/uploads/{upload_id}/original"

        upload = await self._uploads.create(
            user_id=user.id,
            purpose=UploadPurpose(payload.purpose.value),
            storage_bucket=self._settings.storage_bucket,
            storage_key=storage_key,
            content_type=payload.content_type.lower(),
            expires_at=expires_at,
            upload_id=upload_id,
        )

        signed = await self._storage.create_signed_upload(
            key=upload.storage_key,
            content_type=upload.content_type,
            max_bytes=self._settings.max_upload_bytes,
            expires_at=expires_at,
        )
        signed_response = SignedUploadResponse(
            url=signed.url,
            method=signed.method,
            headers=signed.headers,
            expires_at=signed.expires_at,
            max_bytes=signed.max_bytes,
            content_type=signed.content_type,
        )
        response = UploadResponse.from_orm(upload, signed_upload=signed_response)

        if idempotency_key:
            await self._idempotency.put(
                user_id=user.id,
                endpoint=CREATE_ENDPOINT,
                key=idempotency_key,
                request_hash=request_hash,
                response_status=201,
                response_body=response.model_dump(mode="json"),
                expires_at=now + timedelta(days=7),
            )

        return response, 201

    async def get(self, *, user: User, upload_id: uuid.UUID) -> UploadResponse:
        upload = await self._require_owned_upload(user=user, upload_id=upload_id)
        return UploadResponse.from_orm(upload)

    async def refresh_signed_upload(self, *, user: User, upload_id: uuid.UUID) -> UploadResponse:
        upload = await self._require_owned_upload(user=user, upload_id=upload_id)
        if upload.status != UploadStatus.pending:
            raise AppError(
                code="upload_not_ready",
                message="Only pending uploads can refresh a signed upload URL.",
                status_code=422,
                details={"status": upload.status.value},
            )

        now = self._clock.now()
        expires_at = now + timedelta(seconds=self._settings.signed_upload_expiry_seconds)
        signed = await self._storage.create_signed_upload(
            key=upload.storage_key,
            content_type=upload.content_type,
            max_bytes=self._settings.max_upload_bytes,
            expires_at=expires_at,
        )
        upload.expires_at = expires_at
        await self._uploads.save(upload)
        signed_response = SignedUploadResponse(
            url=signed.url,
            method=signed.method,
            headers=signed.headers,
            expires_at=signed.expires_at,
            max_bytes=signed.max_bytes,
            content_type=signed.content_type,
        )
        return UploadResponse.from_orm(upload, signed_upload=signed_response)

    async def complete(self, *, user: User, upload_id: uuid.UUID) -> UploadResponse:
        upload = await self._require_owned_upload(user=user, upload_id=upload_id)
        if upload.status == UploadStatus.ready:
            return UploadResponse.from_orm(upload)
        if upload.status == UploadStatus.consumed:
            raise AppError(
                code="upload_already_consumed",
                message="This upload has already been used.",
                status_code=409,
            )
        if upload.status not in {
            UploadStatus.pending,
            UploadStatus.uploaded,
            UploadStatus.processing,
        }:
            raise AppError(
                code="upload_not_ready",
                message="This upload is not ready to publish yet.",
                status_code=422,
                details={"status": upload.status.value},
            )

        now = self._clock.now()
        if upload.expires_at <= now and upload.status == UploadStatus.pending:
            upload.status = UploadStatus.expired
            await self._uploads.save(upload)
            raise AppError(
                code="upload_not_ready",
                message="This upload is not ready to publish yet.",
                status_code=422,
                details={"status": UploadStatus.expired.value},
            )

        metadata = await self._storage.verify_object(key=upload.storage_key)
        if metadata.byte_size > self._settings.max_upload_bytes:
            raise AppError(
                code="image_too_large",
                message="That image is too large to upload.",
                status_code=422,
            )

        upload.status = UploadStatus.processing
        await self._uploads.save(upload)

        original_bytes = await self._storage.download_object(key=upload.storage_key)
        if len(original_bytes) > self._settings.max_upload_bytes:
            raise AppError(
                code="image_too_large",
                message="That image is too large to upload.",
                status_code=422,
            )

        processed = process_upload_image(
            data=original_bytes,
            declared_content_type=upload.content_type,
        )
        display_key = self._storage.derivative_key(original_key=upload.storage_key, kind="display")
        thumbnail_key = self._storage.derivative_key(
            original_key=upload.storage_key,
            kind="thumbnail",
        )
        await self._storage.put_object(
            key=display_key,
            body=processed.display_bytes,
            content_type=processed.display_content_type,
        )
        await self._storage.put_object(
            key=thumbnail_key,
            body=processed.thumbnail_bytes,
            content_type=processed.thumbnail_content_type,
        )

        checksum = hashlib.sha256(original_bytes).hexdigest()
        upload = await self._uploads.mark_ready(
            upload,
            byte_size=metadata.byte_size,
            width=processed.width,
            height=processed.height,
            checksum=checksum,
            uploaded_at=now,
            verified_at=now,
        )
        return UploadResponse.from_orm(upload)

    def _validate_create_request(self, payload: CreateUploadRequest) -> None:
        content_type = payload.content_type.lower().strip()
        if content_type not in self._settings.allowed_image_content_type_set:
            raise AppError(
                code="unsupported_media_type",
                message="That image type is not supported.",
                status_code=422,
            )
        if payload.byte_size > self._settings.max_upload_bytes:
            raise AppError(
                code="image_too_large",
                message="That image is too large to upload.",
                status_code=422,
            )
        if payload.purpose not in {
            UploadPurposeSchema.submission,
            UploadPurposeSchema.avatar,
        }:
            raise AppError(
                code="validation_error",
                message="That upload purpose is not supported.",
                status_code=422,
            )

    async def _require_owned_upload(self, *, user: User, upload_id: uuid.UUID) -> Upload:
        upload = await self._uploads.get_by_id(upload_id)
        if upload is None or upload.user_id != user.id:
            raise AppError(
                code="upload_not_found",
                message="The requested upload could not be found.",
                status_code=404,
            )
        return upload


def _hash_create_request(payload: CreateUploadRequest) -> str:
    canonical = json.dumps(payload.model_dump(mode="json"), sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()
