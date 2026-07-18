"""Community feed routes."""

from __future__ import annotations

from fastapi import APIRouter, Query

from app.schemas.feed import RecentFeedResponse
from app.services.feed import FeedService

router = APIRouter(tags=["feed"])


@router.get("/feed/recent", response_model=RecentFeedResponse)
async def get_recent_feed(
    cursor: str | None = Query(default=None),
    limit: int = Query(default=20, ge=1, le=50),
) -> RecentFeedResponse:
    return FeedService().recent(cursor=cursor, limit=limit)
