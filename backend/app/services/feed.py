"""Community feed application service."""

from __future__ import annotations

import uuid
from datetime import timedelta

from sqlalchemy.ext.asyncio import AsyncSession

from app.core.clock import Clock
from app.core.pagination import decode_cursor, encode_cursor
from app.core.settings import Settings, get_settings
from app.models.user import User
from app.repositories.likes import LikeRepository
from app.repositories.submissions import SubmissionRepository
from app.repositories.uploads import UploadRepository
from app.schemas.feed import FeedItem, RecentFeedResponse
from app.services.blocks import BlockService
from app.services.feed_items import build_feed_item
from app.services.media_urls import resolve_avatar_urls
from app.storage.base import StorageAdapter


class FeedService:
    """Reverse-chronological community feed over published Submissions."""

    def __init__(
        self,
        session: AsyncSession,
        clock: Clock,
        storage: StorageAdapter,
        settings: Settings | None = None,
    ) -> None:
        self._session = session
        self._submissions = SubmissionRepository(session)
        self._likes = LikeRepository(session)
        self._uploads = UploadRepository(session)
        self._blocks = BlockService(session, clock, settings=settings, storage=storage)
        self._clock = clock
        self._storage = storage
        self._settings = settings or get_settings()

    async def recent(
        self,
        *,
        cursor: str | None = None,
        limit: int = 20,
        viewer: User | None = None,
    ) -> RecentFeedResponse:
        cursor_published_at = None
        cursor_id = None
        if cursor:
            cursor_published_at, cursor_id = decode_cursor(cursor)

        excluded = await self._blocks.exclude_ids_for(viewer.id if viewer else None)

        # Fetch one extra row to detect whether another page exists.
        rows = await self._submissions.list_recent_published(
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
        avatar_upload_ids = [row.user.avatar_upload_id for row in page_rows]
        uploads_by_id = await self._uploads.get_by_ids(
            [upload_id for upload_id in avatar_upload_ids if upload_id is not None]
        )
        avatars_by_upload_id = await resolve_avatar_urls(
            storage=self._storage,
            uploads_by_id=uploads_by_id,
            avatar_upload_ids=avatar_upload_ids,
            expires_at=expires_at,
        )

        items: list[FeedItem] = []
        for row in page_rows:
            avatar_url = None
            if row.user.avatar_upload_id is not None:
                avatar_url = avatars_by_upload_id.get(row.user.avatar_upload_id)
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
