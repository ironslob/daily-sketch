"""Submission application service."""

from __future__ import annotations

import hashlib
import json
import uuid
from datetime import timedelta

from sqlalchemy.ext.asyncio import AsyncSession

from app.core.clock import Clock
from app.core.errors import AppError
from app.core.settings import Settings, get_settings
from app.models.sketch_session import SketchSessionStatus
from app.models.sketch_session_event import SketchSessionEventType
from app.models.submission import SubmissionStatus
from app.models.upload import UploadStatus
from app.models.user import User, UserStatus
from app.repositories.blocks import BlockRepository
from app.repositories.idempotency import IdempotencyRepository
from app.repositories.likes import LikeRepository
from app.repositories.prompts import PromptRepository
from app.repositories.sketch_sessions import SketchSessionRepository
from app.repositories.submissions import SubmissionRepository
from app.repositories.uploads import UploadRepository
from app.repositories.users import UserRepository
from app.schemas.submissions import CreateSubmissionRequest, SubmissionResponse
from app.services.profile import ProfileService
from app.storage.base import StorageAdapter

CREATE_ENDPOINT = "POST /api/v1/submissions"


class SubmissionService:
    def __init__(
        self,
        session: AsyncSession,
        clock: Clock,
        storage: StorageAdapter,
        settings: Settings | None = None,
    ) -> None:
        self._session = session
        self._submissions = SubmissionRepository(session)
        self._uploads = UploadRepository(session)
        self._sessions = SketchSessionRepository(session)
        self._prompts = PromptRepository(session)
        self._users = UserRepository(session)
        self._likes = LikeRepository(session)
        self._blocks = BlockRepository(session)
        self._idempotency = IdempotencyRepository(session)
        self._clock = clock
        self._storage = storage
        self._settings = settings or get_settings()

    async def create(
        self,
        *,
        user: User,
        payload: CreateSubmissionRequest,
        idempotency_key: str | None,
    ) -> tuple[SubmissionResponse, int]:
        ProfileService.require_complete_profile(user)

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
                return (
                    SubmissionResponse.model_validate(existing.response_body),
                    existing.response_status,
                )

        caption = _normalise_caption(payload.caption, self._settings.caption_max_length)
        sketch_session = await self._sessions.get_by_id(payload.sketch_session_id)
        if sketch_session is None or sketch_session.user_id != user.id:
            raise AppError(
                code="session_not_found",
                message="The requested sketch session could not be found.",
                status_code=404,
            )

        existing_submission = await self._submissions.get_by_sketch_session_id(sketch_session.id)
        if existing_submission is not None:
            raise AppError(
                code="session_already_submitted",
                message="This sketch session already has a published submission.",
                status_code=409,
            )

        if sketch_session.status in {
            SketchSessionStatus.abandoned,
            SketchSessionStatus.expired,
            SketchSessionStatus.completed,
        }:
            raise AppError(
                code="invalid_session_transition",
                message="That lifecycle event is not valid for the current session state.",
                status_code=422,
                details={"status": sketch_session.status.value},
            )

        upload = await self._uploads.get_by_id(payload.upload_id)
        if upload is None or upload.user_id != user.id:
            raise AppError(
                code="upload_not_found",
                message="The requested upload could not be found.",
                status_code=404,
            )
        if upload.status == UploadStatus.consumed:
            raise AppError(
                code="upload_already_consumed",
                message="This upload has already been used.",
                status_code=409,
            )
        if upload.status != UploadStatus.ready:
            raise AppError(
                code="upload_not_ready",
                message="This upload is not ready to publish yet.",
                status_code=422,
                details={"status": upload.status.value},
            )

        prompt = await self._prompts.get_published_by_id(sketch_session.prompt_id)
        if prompt is None:
            raise AppError(
                code="prompt_not_found",
                message="The requested prompt could not be found.",
                status_code=404,
            )

        now = self._clock.now()
        submission = await self._submissions.create(
            user_id=user.id,
            prompt_id=prompt.id,
            sketch_session_id=sketch_session.id,
            upload_id=upload.id,
            caption=caption,
            published_at=now,
            commit=False,
        )
        await self._uploads.mark_consumed(upload, consumed_at=now, commit=False)

        await self._sessions.add_event(
            sketch_session=sketch_session,
            event_type=SketchSessionEventType.submission_created,
            occurred_at=now,
        )
        sketch_session.status = SketchSessionStatus.completed
        sketch_session.completed_at = now
        if sketch_session.upload_completed_at is None:
            sketch_session.upload_completed_at = now
        await self._sessions.save(sketch_session, commit=False)
        await self._session.commit()
        await self._session.refresh(submission)

        response = await self._to_response(
            submission_id=submission.id,
            viewer=user,
        )

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

    async def get(
        self,
        *,
        submission_id: uuid.UUID,
        viewer: User | None,
    ) -> SubmissionResponse:
        return await self._to_response(submission_id=submission_id, viewer=viewer)

    async def delete(self, *, user: User, submission_id: uuid.UUID) -> None:
        submission = await self._submissions.get_by_id(submission_id)
        if submission is None or submission.status == SubmissionStatus.deleted:
            raise AppError(
                code="submission_not_found",
                message="The requested sketch could not be found.",
                status_code=404,
            )
        if submission.user_id != user.id:
            raise AppError(
                code="submission_not_found",
                message="The requested sketch could not be found.",
                status_code=404,
            )

        now = self._clock.now()
        await self._submissions.soft_delete(submission, deleted_at=now)

        upload = await self._uploads.get_by_id(submission.upload_id)
        if upload is not None:
            display_key = self._storage.derivative_key(
                original_key=upload.storage_key,
                kind="display",
            )
            thumbnail_key = self._storage.derivative_key(
                original_key=upload.storage_key,
                kind="thumbnail",
            )
            for key in (upload.storage_key, display_key, thumbnail_key):
                try:
                    await self._storage.delete_object(key=key)
                except Exception:  # best-effort cleanup; retention jobs reconcile later
                    pass

    async def _to_response(
        self,
        *,
        submission_id: uuid.UUID,
        viewer: User | None,
    ) -> SubmissionResponse:
        submission = await self._submissions.get_by_id(submission_id)
        if (
            submission is None
            or submission.status != SubmissionStatus.published
            or submission.deleted_at is not None
        ):
            raise AppError(
                code="submission_not_found",
                message="The requested sketch could not be found.",
                status_code=404,
            )

        user = await self._users.get_by_id(submission.user_id)
        prompt = await self._prompts.get_by_id(submission.prompt_id)
        sketch_session = await self._sessions.get_by_id(submission.sketch_session_id)
        upload = await self._uploads.get_by_id(submission.upload_id)
        if (
            user is None
            or prompt is None
            or sketch_session is None
            or upload is None
            or user.deleted_at is not None
            or user.status
            not in {
                UserStatus.incomplete,
                UserStatus.active,
            }
        ):
            raise AppError(
                code="submission_not_found",
                message="The requested sketch could not be found.",
                status_code=404,
            )

        if viewer is not None and await self._blocks.either_direction_exists(
            user_a=viewer.id,
            user_b=submission.user_id,
        ):
            raise AppError(
                code="submission_not_found",
                message="The requested sketch could not be found.",
                status_code=404,
            )

        expires_at = self._clock.now() + timedelta(
            seconds=self._settings.signed_read_expiry_seconds
        )
        display_key = self._storage.derivative_key(
            original_key=upload.storage_key,
            kind="display",
        )
        thumbnail_key = self._storage.derivative_key(
            original_key=upload.storage_key,
            kind="thumbnail",
        )
        image_url = await self._storage.read_url(key=display_key, expires_at=expires_at)
        thumbnail_url = await self._storage.read_url(
            key=thumbnail_key,
            expires_at=expires_at,
        )
        avatar_url = None
        if user.avatar_upload_id is not None:
            avatar_upload = await self._uploads.get_by_id(user.avatar_upload_id)
            if avatar_upload is not None:
                avatar_display_key = self._storage.derivative_key(
                    original_key=avatar_upload.storage_key,
                    kind="display",
                )
                avatar_url = await self._storage.read_url(
                    key=avatar_display_key,
                    expires_at=expires_at,
                )
        is_owner = viewer is not None and viewer.id == submission.user_id
        viewer_has_liked = False
        if viewer is not None:
            viewer_has_liked = await self._likes.exists(
                submission_id=submission.id,
                user_id=viewer.id,
            )
        return SubmissionResponse.from_parts(
            submission=submission,
            user=user,
            prompt=prompt,
            sketch_session=sketch_session,
            image_url=image_url,
            thumbnail_url=thumbnail_url,
            is_owner=is_owner,
            viewer_has_liked=viewer_has_liked,
            avatar_url=avatar_url,
        )


def _hash_create_request(payload: CreateSubmissionRequest) -> str:
    canonical = json.dumps(payload.model_dump(mode="json"), sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def _normalise_caption(caption: str | None, max_length: int) -> str | None:
    if caption is None:
        return None
    stripped = caption.strip()
    if not stripped:
        return None
    if len(stripped) > max_length:
        raise AppError(
            code="validation_error",
            message="The request could not be validated.",
            status_code=422,
            details={"caption": "too_long"},
        )
    return stripped
