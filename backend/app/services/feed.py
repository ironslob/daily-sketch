"""Community feed application service."""

from __future__ import annotations

from app.schemas.feed import RecentFeedResponse


class FeedService:
    """Phase 4 feed returns an empty page until Submissions exist."""

    def recent(self, *, cursor: str | None = None, limit: int = 20) -> RecentFeedResponse:
        _ = cursor, limit
        return RecentFeedResponse(items=[], next_cursor=None)
