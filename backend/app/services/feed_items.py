"""Shared feed-item projection helpers."""

from __future__ import annotations

from datetime import datetime

from app.models.enums import TimerMode
from app.models.user import User
from app.repositories.publications import FeedRow
from app.schemas.feed import FeedItem
from app.schemas.feed_shared import FeedPromptSummary, FeedUserSummary
from app.schemas.me import TimerModeSchema
from app.schemas.submissions import CreativeTypeSchema
from app.services.media_urls import signed_display_url, signed_thumbnail_url
from app.storage.base import StorageAdapter

CAPTION_PREVIEW_MAX_LENGTH = 140


def caption_preview(caption: str | None) -> str | None:
    """Truncate a caption for feed/profile display."""
    if caption is None:
        return None
    stripped = caption.strip()
    if not stripped:
        return None
    if len(stripped) <= CAPTION_PREVIEW_MAX_LENGTH:
        return stripped
    return f"{stripped[: CAPTION_PREVIEW_MAX_LENGTH - 1]}…"


async def build_feed_item(
    *,
    row: FeedRow,
    viewer: User | None,
    storage: StorageAdapter,
    expires_at: datetime,
    viewer_has_liked: bool,
    avatar_url: str | None = None,
) -> FeedItem:
    """Build a FeedItem from a joined feed/profile row."""
    image_url = None
    thumbnail_url = None
    if row.upload is not None:
        image_url = await signed_display_url(
            storage=storage,
            original_key=row.upload.storage_key,
            expires_at=expires_at,
        )
        thumbnail_url = await signed_thumbnail_url(
            storage=storage,
            original_key=row.upload.storage_key,
            expires_at=expires_at,
        )

    session = row.sketch_session or row.story_session
    if session is not None:
        timer_mode = TimerModeSchema(session.timer_mode.value)
        if session.timer_mode == TimerMode.no_timer:
            timer_seconds = None
        else:
            timer_seconds = session.selected_timer_seconds
    else:
        timer_mode = TimerModeSchema.no_timer
        timer_seconds = None

    is_owner = viewer is not None and viewer.id == row.publication.user_id
    creative_type = CreativeTypeSchema(row.publication.creative_type.value)

    caption = None
    body_preview_text = None
    word_count = None
    if row.sketch_submission is not None:
        caption = row.sketch_submission.caption
    if row.story_submission is not None:
        caption = row.story_submission.caption
        body_preview_text = caption_preview(row.story_submission.body)
        word_count = len(row.story_submission.body.split())

    return FeedItem(
        id=row.publication.id,
        creative_type=creative_type,
        image_url=image_url,
        thumbnail_url=thumbnail_url,
        user=FeedUserSummary(
            id=row.user.id,
            username=row.user.username or "",
            display_name=row.user.display_name,
            avatar_url=avatar_url,
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
        caption_preview=caption_preview(caption),
        body_preview=body_preview_text,
        word_count=word_count,
        like_count=row.publication.like_count,
        reflection_count=row.publication.reflection_count,
        viewer_has_liked=viewer_has_liked,
        is_owner=is_owner,
        published_at=row.publication.published_at,
    )
