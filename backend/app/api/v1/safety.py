"""Reports and blocking routes."""

from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.deps import get_current_user
from app.core.clock import Clock, get_clock
from app.core.settings import Settings, get_settings
from app.db.session import get_db_session
from app.models.user import User
from app.schemas.safety import (
    BlockedUsersResponse,
    BlockState,
    CreateReportRequest,
    ReportResponse,
)
from app.services.blocks import BlockService
from app.services.reports import ReportService
from app.storage.base import StorageAdapter, get_storage_adapter

router = APIRouter()


@router.post("/reports", response_model=ReportResponse, status_code=201, tags=["reports"])
async def create_report(
    payload: CreateReportRequest,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db_session),
) -> ReportResponse:
    return await ReportService(session).create(reporter=user, payload=payload)


@router.get("/me/blocked-users", response_model=BlockedUsersResponse, tags=["me"])
async def list_blocked_users(
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db_session),
    clock: Clock = Depends(get_clock),
    settings: Settings = Depends(get_settings),
    storage: StorageAdapter = Depends(get_storage_adapter),
) -> BlockedUsersResponse:
    return await BlockService(session, clock, settings, storage).list_blocked_users(blocker=user)


@router.put("/users/{user_id}/block", response_model=BlockState, tags=["users"])
async def block_user(
    user_id: UUID,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db_session),
    clock: Clock = Depends(get_clock),
    settings: Settings = Depends(get_settings),
    storage: StorageAdapter = Depends(get_storage_adapter),
) -> BlockState:
    return await BlockService(session, clock, settings, storage).block(
        blocker=user,
        user_id=user_id,
    )


@router.delete("/users/{user_id}/block", response_model=BlockState, tags=["users"])
async def unblock_user(
    user_id: UUID,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db_session),
    clock: Clock = Depends(get_clock),
    settings: Settings = Depends(get_settings),
    storage: StorageAdapter = Depends(get_storage_adapter),
) -> BlockState:
    return await BlockService(session, clock, settings, storage).unblock(
        blocker=user,
        user_id=user_id,
    )
