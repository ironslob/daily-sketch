"""Community feed routes."""

from __future__ import annotations

from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.deps import get_optional_current_user
from app.core.clock import Clock, get_clock
from app.core.settings import Settings, get_settings
from app.db.session import get_db_session
from app.models.user import User
from app.schemas.feed import RecentFeedResponse
from app.services.feed import FeedService
from app.storage.base import StorageAdapter, get_storage_adapter

router = APIRouter(tags=["feed"])


@router.get("/feed/recent", response_model=RecentFeedResponse)
async def get_recent_feed(
    cursor: str | None = Query(default=None),
    limit: int = Query(default=20, ge=1, le=50),
    viewer: User | None = Depends(get_optional_current_user),
    session: AsyncSession = Depends(get_db_session),
    clock: Clock = Depends(get_clock),
    storage: StorageAdapter = Depends(get_storage_adapter),
    settings: Settings = Depends(get_settings),
) -> RecentFeedResponse:
    return await FeedService(session, clock, storage, settings).recent(
        cursor=cursor,
        limit=limit,
        viewer=viewer,
    )
