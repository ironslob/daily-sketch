"""Account deletion application service."""

from __future__ import annotations

import logging
from datetime import datetime, timedelta

from sqlalchemy.ext.asyncio import AsyncSession

from app.core.clock import Clock
from app.core.settings import Settings, get_settings
from app.models.submission import SubmissionStatus
from app.models.user import User, UserStatus
from app.repositories.idempotency import IdempotencyRepository
from app.repositories.likes import LikeRepository
from app.repositories.reflections import ReflectionRepository
from app.repositories.submissions import SubmissionRepository
from app.repositories.uploads import UploadRepository
from app.repositories.users import UserRepository
from app.schemas.safety import AccountDeletionResponse, AccountDeletionStatus
from app.storage.base import StorageAdapter

logger = logging.getLogger(__name__)

DELETE_ME_ENDPOINT = "DELETE /api/v1/me"
DELETION_MESSAGE = "Your account deletion has been scheduled."


class AccountDeletionService:
    def __init__(
        self,
        session: AsyncSession,
        clock: Clock,
        settings: Settings | None = None,
        storage: StorageAdapter | None = None,
    ) -> None:
        self._session = session
        self._clock = clock
        self._settings = settings or get_settings()
        self._storage = storage
        self._users = UserRepository(session)
        self._submissions = SubmissionRepository(session)
        self._reflections = ReflectionRepository(session)
        self._likes = LikeRepository(session)
        self._uploads = UploadRepository(session)
        self._idempotency = IdempotencyRepository(session)

    async def request_deletion(
        self,
        *,
        user: User,
        idempotency_key: str | None = None,
    ) -> tuple[AccountDeletionResponse, int]:
        if user.status in {UserStatus.pending_deletion, UserStatus.deleted}:
            response = AccountDeletionResponse(
                status=AccountDeletionStatus.pending_deletion,
                message=DELETION_MESSAGE,
            )
            return response, 202

        if idempotency_key:
            existing = await self._idempotency.get(
                user_id=user.id,
                endpoint=DELETE_ME_ENDPOINT,
                key=idempotency_key,
            )
            if existing is not None and existing.response_body is not None:
                return (
                    AccountDeletionResponse.model_validate(existing.response_body),
                    existing.response_status or 202,
                )

        now = self._clock.now()
        await self._hide_user_content(user=user, now=now)
        await self._users.set_status(
            user,
            status=UserStatus.pending_deletion,
            deleted_at=now,
            commit=False,
        )
        await self._session.commit()

        response = AccountDeletionResponse(
            status=AccountDeletionStatus.pending_deletion,
            message=DELETION_MESSAGE,
        )
        if idempotency_key:
            await self._idempotency.put(
                user_id=user.id,
                endpoint=DELETE_ME_ENDPOINT,
                key=idempotency_key,
                request_hash="delete-account",
                response_status=202,
                response_body=response.model_dump(mode="json"),
                expires_at=now + timedelta(days=7),
            )
        return response, 202

    async def finalize_pending(self, *, dry_run: bool = False) -> int:
        """Finalize all pending-deletion accounts. Returns count finalized."""
        pending = await self._users.list_pending_deletion()
        if dry_run:
            return len(pending)
        finalized = 0
        for user in pending:
            await self._finalize_user(user)
            finalized += 1
        return finalized

    async def _hide_user_content(self, *, user: User, now: datetime) -> None:
        submissions = await self._submissions.list_published_for_user_ids(user.id)
        for submission in submissions:
            await self._submissions.set_status(
                submission,
                status=SubmissionStatus.hidden,
                commit=False,
            )

        reflections = await self._reflections.list_published_for_user(user.id)
        for reflection in reflections:
            transitioned = await self._reflections.soft_delete(
                reflection,
                deleted_at=now,
                commit=False,
            )
            if transitioned:
                reflection_submission = await self._submissions.get_by_id(reflection.submission_id)
                if reflection_submission is not None:
                    reflection_submission.reflection_count = max(
                        0, reflection_submission.reflection_count - 1
                    )

        likes = await self._likes.list_for_user(user.id)
        for like in likes:
            deleted = await self._likes.delete(
                submission_id=like.submission_id,
                user_id=user.id,
                commit=False,
            )
            if deleted:
                like_submission = await self._submissions.get_by_id(like.submission_id)
                if like_submission is not None:
                    like_submission.like_count = max(0, like_submission.like_count - 1)

    async def _finalize_user(self, user: User) -> None:
        if user.status == UserStatus.deleted:
            return

        # Best-effort media cleanup for all owned submissions + avatar.
        rows = await self._submissions.list_user_published(
            user_id=user.id,
            limit=10_000,
        )
        # Also load any non-published with uploads via direct IDs when needed.
        from sqlalchemy import select

        from app.models.submission import Submission

        result = await self._session.execute(
            select(Submission).where(Submission.user_id == user.id)
        )
        all_submissions = list(result.scalars().all())
        _ = rows
        for submission in all_submissions:
            upload = await self._uploads.get_by_id(submission.upload_id)
            if upload is not None and self._storage is not None:
                for key in (
                    upload.storage_key,
                    self._storage.derivative_key(original_key=upload.storage_key, kind="display"),
                    self._storage.derivative_key(
                        original_key=upload.storage_key,
                        kind="thumbnail",
                    ),
                ):
                    try:
                        await self._storage.delete_object(key=key)
                    except Exception:
                        logger.exception("Failed to delete media key during account finalize")
                if upload.deleted_at is None:
                    upload.deleted_at = self._clock.now()
            if submission.status != SubmissionStatus.deleted:
                await self._submissions.set_status(
                    submission,
                    status=SubmissionStatus.deleted,
                    deleted_at=self._clock.now(),
                    commit=False,
                )

        if user.avatar_upload_id is not None and self._storage is not None:
            avatar = await self._uploads.get_by_id(user.avatar_upload_id)
            if avatar is not None:
                for key in (
                    avatar.storage_key,
                    self._storage.derivative_key(original_key=avatar.storage_key, kind="display"),
                    self._storage.derivative_key(
                        original_key=avatar.storage_key,
                        kind="thumbnail",
                    ),
                ):
                    try:
                        await self._storage.delete_object(key=key)
                    except Exception:
                        logger.exception("Failed to delete avatar key during account finalize")
                if avatar.deleted_at is None:
                    avatar.deleted_at = self._clock.now()

        # Descope identity coordination seam — no-op without management credentials.
        self._coordinate_descope_deletion(user)

        await self._users.set_status(
            user,
            status=UserStatus.deleted,
            deleted_at=user.deleted_at or self._clock.now(),
            commit=True,
        )

    def _coordinate_descope_deletion(self, user: User) -> None:
        """Best-effort Descope disable/delete. No-op when management creds are absent."""
        # Version one records intent only; management API integration is optional.
        logger.info(
            "account_deletion_descope_seam user_id=%s descope_subject=%s",
            user.id,
            user.descope_subject,
        )
