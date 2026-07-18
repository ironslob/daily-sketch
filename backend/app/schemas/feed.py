"""Community feed API schemas."""

from __future__ import annotations

from datetime import date, datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field

from app.schemas.me import TimerModeSchema


class FeedUserSummary(BaseModel):
    """Compact public user projection embedded in feed items."""

    model_config = ConfigDict(extra="forbid")

    id: UUID
    username: str
    display_name: str
    avatar_url: str | None = None


class FeedPromptSummary(BaseModel):
    """Compact Prompt projection embedded in feed items."""

    model_config = ConfigDict(extra="forbid")

    id: UUID
    prompt_date: date
    word_1: str
    word_2: str
    word_3: str


class FeedItem(BaseModel):
    """Forward-compatible feed projection for a published Submission."""

    model_config = ConfigDict(extra="forbid")

    id: UUID
    image_url: str
    thumbnail_url: str
    user: FeedUserSummary
    prompt: FeedPromptSummary
    timer_mode: TimerModeSchema
    timer_seconds: int | None = None
    caption_preview: str | None = None
    like_count: int = Field(ge=0)
    reflection_count: int = Field(ge=0)
    viewer_has_liked: bool
    is_owner: bool
    published_at: datetime


class RecentFeedResponse(BaseModel):
    """Cursor-paginated recent community feed page."""

    model_config = ConfigDict(extra="forbid")

    items: list[FeedItem]
    next_cursor: str | None = None
