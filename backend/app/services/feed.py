"""Community feed application service."""

from __future__ import annotations

from datetime import datetime, timedelta

from sqlalchemy.ext.asyncio import AsyncSession

from app.core.clock import Clock
from app.core.pagination import decode_cursor, encode_cursor
from app.core.settings import Settings, get_settings
from app.models.enums import TimerMode
from app.models.user import User
from app.repositories.submissions import FeedRow, SubmissionRepository
from app.schemas.feed import FeedItem, FeedPromptSummary, FeedUserSummary, RecentFeedResponse
from app.schemas.me import TimerModeSchema
from app.storage.base import StorageAdapter

CAPTION_PREVIEW_MAX_LENGTH = 140


class FeedService:
    """Reverse-chronological community feed over published Submissions."""

    def __init__(
        self,
        session: AsyncSession,
        clock: Clock,
        storage: StorageAdapter,
        settings: Settings | None = None,
    ) -> None:
        self._submissions = SubmissionRepository(session)
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

        # Fetch one extra row to detect whether another page exists.
        rows = await self._submissions.list_recent_published(
            limit=limit + 1,
            cursor_published_at=cursor_published_at,
            cursor_id=cursor_id,
            viewer_id=viewer.id if viewer is not None else None,
        )

        page_rows = rows[:limit]
        next_cursor: str | None = None
        if len(rows) > limit:
            last = page_rows[-1].submission
            next_cursor = encode_cursor(
                published_at=last.published_at,
                submission_id=last.id,
            )

        expires_at = self._clock.now() + timedelta(
            seconds=self._settings.signed_read_expiry_seconds
        )
        items: list[FeedItem] = []
        for row in page_rows:
            items.append(await self._to_feed_item(row=row, viewer=viewer, expires_at=expires_at))

        return RecentFeedResponse(items=items, next_cursor=next_cursor)

    async def _to_feed_item(
        self,
        *,
        row: FeedRow,
        viewer: User | None,
        expires_at: datetime,
    ) -> FeedItem:
        display_key = self._storage.derivative_key(
            original_key=row.upload.storage_key,
            kind="display",
        )
        thumbnail_key = self._storage.derivative_key(
            original_key=row.upload.storage_key,
            kind="thumbnail",
        )
        image_url = await self._storage.read_url(key=display_key, expires_at=expires_at)
        thumbnail_url = await self._storage.read_url(
            key=thumbnail_key,
            expires_at=expires_at,
        )

        timer_mode = TimerModeSchema(row.sketch_session.timer_mode.value)
        if row.sketch_session.timer_mode == TimerMode.no_timer:
            timer_seconds = None
        else:
            timer_seconds = row.sketch_session.selected_timer_seconds

        is_owner = viewer is not None and viewer.id == row.submission.user_id
        return FeedItem(
            id=row.submission.id,
            image_url=image_url,
            thumbnail_url=thumbnail_url,
            user=FeedUserSummary(
                id=row.user.id,
                username=row.user.username or "",
                display_name=row.user.display_name,
                avatar_url=None,
            ),
            prompt=FeedPromptSummary(
                id=row.prompt.id,
                prompt_date=row.prompt.prompt_date,
                word_1=row.prompt.word_1,
                word_2=row.prompt.word_2,
                word_3=row.prompt.word_3,
            ),
            timer_mode=timer_mode,
            timer_seconds=timer_seconds,
            caption_preview=caption_preview(row.submission.caption),
            like_count=row.submission.like_count,
            reflection_count=row.submission.reflection_count,
            viewer_has_liked=False,  # Phase 9 adds real Like state.
            is_owner=is_owner,
            published_at=row.submission.published_at,
        )


def caption_preview(caption: str | None) -> str | None:
    """Truncate a caption for feed display."""
    if caption is None:
        return None
    stripped = caption.strip()
    if not stripped:
        return None
    if len(stripped) <= CAPTION_PREVIEW_MAX_LENGTH:
        return stripped
    return f"{stripped[: CAPTION_PREVIEW_MAX_LENGTH - 1]}…"
