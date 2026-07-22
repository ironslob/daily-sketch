"""Likes and Reflections API schemas."""

from __future__ import annotations

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field

from app.schemas.feed_shared import FeedUserSummary


class LikeState(BaseModel):
    model_config = ConfigDict(extra="forbid")

    liked: bool
    like_count: int = Field(ge=0)


class CreateReflectionRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    body: str = Field(min_length=1, max_length=500)


class ReflectionResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: UUID
    submission_id: UUID
    user: FeedUserSummary
    body: str
    created_at: datetime
    is_author: bool


class ReflectionListResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    items: list[ReflectionResponse]
    next_cursor: str | None = None
