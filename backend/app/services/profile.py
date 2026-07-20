"""Profile application services."""

from __future__ import annotations

import uuid
from datetime import datetime, timedelta, timezone

from sqlalchemy.ext.asyncio import AsyncSession

from app.core.clock import Clock, SystemClock
from app.core.errors import AppError
from app.core.pagination import decode_cursor, encode_cursor
from app.core.settings import Settings, get_settings
from app.core.usernames import (
    is_reserved_username,
    is_valid_username_format,
    normalize_username,
)
from app.models.upload import UploadPurpose, UploadStatus
from app.models.user import User, UserStatus
from app.repositories.likes import LikeRepository
from app.repositories.submissions import SubmissionRepository
from app.repositories.uploads import UploadRepository
from app.repositories.users import UserRepository
from app.schemas.feed import FeedItem, RecentFeedResponse
from app.schemas.me import (
    CurrentUserResponse,
    PreferencesSummary,
    PublicUserResponse,
    UpdateMeRequest,
)
from app.services.blocks import BlockService
from app.services.feed_items import build_feed_item
from app.services.media_urls import resolve_avatar_url
from app.services.preferences import PreferencesService
from app.services.streaks import compute_current_streak
from app.storage.base import StorageAdapter


class ProfileService:
    def __init__(
        self,
        session: AsyncSession,
        *,
        clock: Clock | None = None,
        storage: StorageAdapter | None = None,
        settings: Settings | None = None,
    ) -> None:
        self._session = session
        self._users = UserRepository(session)
        self._uploads = UploadRepository(session)
        self._submissions = SubmissionRepository(session)
        self._likes = LikeRepository(session)
        self._preferences_service = PreferencesService(session)
        self._clock = clock or SystemClock()
        self._storage = storage
        self._settings = settings or get_settings()
        self._blocks = BlockService(
            session,
            self._clock,
            settings=self._settings,
            storage=storage,
        )

    async def get_current_user_response(self, user: User) -> CurrentUserResponse:
        prefs = await self._preferences_service.get_or_create(user.id)
        avatar_url = await self._resolve_user_avatar_url(user)
        return CurrentUserResponse.from_user(
            user,
            PreferencesSummary.from_orm_prefs(prefs),
            avatar_url=avatar_url,
        )

    async def update_me(self, user: User, payload: UpdateMeRequest) -> CurrentUserResponse:
        username = payload.username
        username_normalized: str | None = None
        if username is not None:
            stripped = username.strip()
            if not is_valid_username_format(stripped):
                raise AppError(
                    code="username_invalid",
                    message=(
                        "Usernames must be 3–30 characters and use only "
                        "letters, numbers, and underscores."
                    ),
                    status_code=422,
                )
            if is_reserved_username(stripped):
                raise AppError(
                    code="username_reserved",
                    message="That username is reserved.",
                    status_code=422,
                )
            username_normalized = normalize_username(stripped)
            existing = await self._users.get_by_username_normalized(username_normalized)
            if existing is not None and existing.id != user.id:
                raise AppError(
                    code="username_taken",
                    message="That username is already taken.",
                    status_code=409,
                )
            username = stripped

        display_name = payload.display_name
        if display_name is not None:
            display_name = display_name.strip()
            if not display_name:
                raise AppError(
                    code="validation_error",
                    message="Display name cannot be empty.",
                    status_code=422,
                )

        bio_sentinel: object = ...
        if "bio" in payload.model_fields_set:
            bio_sentinel = payload.bio

        avatar_upload_id_sentinel: object = ...
        if "avatar_upload_id" in payload.model_fields_set:
            assert payload.avatar_upload_id is not None
            avatar_upload_id_sentinel = await self._consume_avatar_upload(
                user=user,
                avatar_upload_id=payload.avatar_upload_id,
            )

        effective_username = username if username is not None else user.username
        effective_display = display_name if display_name is not None else user.display_name
        should_complete = (
            effective_username is not None
            and bool(effective_display)
            and user.profile_completed_at is None
        )

        status_update: UserStatus | None = None
        completed_at: datetime | None | object = ...
        if should_complete:
            completed_at = datetime.now(timezone.utc)
            if user.status == UserStatus.incomplete:
                status_update = UserStatus.active

        await self._users.update_profile(
            user,
            username=username,
            username_normalized=username_normalized,
            display_name=display_name,
            bio=bio_sentinel,
            avatar_upload_id=avatar_upload_id_sentinel,
            status=status_update,
            profile_completed_at=completed_at,
        )
        return await self.get_current_user_response(user)

    async def get_public_user(
        self,
        username: str,
        *,
        viewer: User | None = None,
    ) -> PublicUserResponse:
        user = await self._require_public_profile(username, viewer=viewer)
        submission_count = await self._submissions.count_user_published(user.id)
        prompt_dates = await self._submissions.published_prompt_dates(user.id)
        current_streak = compute_current_streak(prompt_dates, today=self._clock.today())
        avatar_url = await self._resolve_user_avatar_url(user)
        return PublicUserResponse(
            id=user.id,
            username=user.username or "",
            display_name=user.display_name,
            bio=user.bio,
            avatar_url=avatar_url,
            submission_count=submission_count,
            current_streak=current_streak,
            is_self=viewer is not None and viewer.id == user.id,
        )

    async def get_user_submissions(
        self,
        username: str,
        *,
        cursor: str | None = None,
        limit: int = 20,
        viewer: User | None = None,
    ) -> RecentFeedResponse:
        if self._storage is None:
            raise RuntimeError("Storage adapter is required for profile submissions")

        user = await self._require_public_profile(username, viewer=viewer)
        cursor_published_at = None
        cursor_id = None
        if cursor:
            cursor_published_at, cursor_id = decode_cursor(cursor)

        excluded = await self._blocks.exclude_ids_for(viewer.id if viewer else None)
        rows = await self._submissions.list_user_published(
            user_id=user.id,
            limit=limit + 1,
            cursor_published_at=cursor_published_at,
            cursor_id=cursor_id,
            viewer_id=viewer.id if viewer is not None else None,
            excluded_author_ids=excluded or None,
        )
        page_rows = rows[:limit]
        next_cursor: str | None = None
        if len(rows) > limit:
            last = page_rows[-1].submission
            next_cursor = encode_cursor(
                published_at=last.published_at,
                submission_id=last.id,
            )

        liked_ids: set[uuid.UUID] = set()
        if viewer is not None and page_rows:
            liked_ids = await self._likes.liked_submission_ids(
                user_id=viewer.id,
                submission_ids=[row.submission.id for row in page_rows],
            )

        expires_at = self._clock.now() + timedelta(
            seconds=self._settings.signed_read_expiry_seconds
        )
        avatar_url = await self._resolve_user_avatar_url(user, expires_at=expires_at)

        items: list[FeedItem] = []
        for row in page_rows:
            items.append(
                await build_feed_item(
                    row=row,
                    viewer=viewer,
                    storage=self._storage,
                    expires_at=expires_at,
                    viewer_has_liked=row.submission.id in liked_ids,
                    avatar_url=avatar_url,
                )
            )
        return RecentFeedResponse(items=items, next_cursor=next_cursor)

    async def _require_public_profile(
        self,
        username: str,
        *,
        viewer: User | None = None,
    ) -> User:
        normalized = normalize_username(username)
        user = await self._users.get_by_username_normalized(normalized)
        if (
            user is None
            or user.username is None
            or user.status != UserStatus.active
            or user.profile_completed_at is None
            or user.deleted_at is not None
        ):
            raise AppError(
                code="user_not_found",
                message="The requested profile could not be found.",
                status_code=404,
            )
        if viewer is not None and await self._blocks.is_blocked_either_way(
            viewer_id=viewer.id,
            other_id=user.id,
        ):
            raise AppError(
                code="user_not_found",
                message="The requested profile could not be found.",
                status_code=404,
            )
        return user

    async def _consume_avatar_upload(
        self,
        *,
        user: User,
        avatar_upload_id: uuid.UUID,
    ) -> uuid.UUID:
        # Idempotent retry: same avatar already attached and previously consumed.
        if user.avatar_upload_id == avatar_upload_id:
            existing = await self._uploads.get_by_id(avatar_upload_id)
            if (
                existing is not None
                and existing.user_id == user.id
                and existing.purpose == UploadPurpose.avatar
                and existing.status == UploadStatus.consumed
            ):
                return avatar_upload_id

        upload = await self._uploads.get_by_id(avatar_upload_id)
        if upload is None or upload.user_id != user.id:
            raise AppError(
                code="upload_not_found",
                message="The requested upload could not be found.",
                status_code=404,
            )
        if upload.purpose != UploadPurpose.avatar:
            raise AppError(
                code="avatar_upload_invalid",
                message="That upload cannot be used as an avatar.",
                status_code=422,
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

        await self._uploads.mark_consumed(
            upload,
            consumed_at=self._clock.now(),
            commit=False,
        )
        return avatar_upload_id

    async def _resolve_user_avatar_url(
        self,
        user: User,
        *,
        expires_at: datetime | None = None,
    ) -> str | None:
        if self._storage is None or user.avatar_upload_id is None:
            return None
        upload = await self._uploads.get_by_id(user.avatar_upload_id)
        expiry = expires_at or (
            self._clock.now() + timedelta(seconds=self._settings.signed_read_expiry_seconds)
        )
        return await resolve_avatar_url(
            storage=self._storage,
            upload=upload,
            expires_at=expiry,
        )

    @staticmethod
    def require_complete_profile(user: User) -> None:
        """Guard for publish and other complete-profile-required writes."""
        if user.profile_completed_at is None or user.status == UserStatus.incomplete:
            raise AppError(
                code="profile_incomplete",
                message="Complete your profile before publishing.",
                status_code=403,
            )
