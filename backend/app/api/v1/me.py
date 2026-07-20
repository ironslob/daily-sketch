"""Current-user and preferences routes."""

from fastapi import APIRouter, Depends, Header, Response
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.deps import get_current_user, get_current_user_allowing_pending_deletion
from app.core.clock import Clock, get_clock
from app.core.settings import Settings, get_settings
from app.db.session import get_db_session
from app.models.user import User
from app.schemas.me import (
    CurrentUserResponse,
    PreferencesSummary,
    PreferencesUpdateRequest,
    UpdateMeRequest,
)
from app.schemas.safety import AccountDeletionResponse
from app.services.account_deletion import AccountDeletionService
from app.services.preferences import PreferencesService
from app.services.profile import ProfileService
from app.storage.base import StorageAdapter, get_storage_adapter

router = APIRouter(tags=["me"])


@router.get("/me", response_model=CurrentUserResponse)
async def get_me(
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db_session),
    clock: Clock = Depends(get_clock),
    storage: StorageAdapter = Depends(get_storage_adapter),
    settings: Settings = Depends(get_settings),
) -> CurrentUserResponse:
    return await ProfileService(
        session,
        clock=clock,
        storage=storage,
        settings=settings,
    ).get_current_user_response(user)


@router.patch("/me", response_model=CurrentUserResponse)
async def update_me(
    payload: UpdateMeRequest,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db_session),
    clock: Clock = Depends(get_clock),
    storage: StorageAdapter = Depends(get_storage_adapter),
    settings: Settings = Depends(get_settings),
) -> CurrentUserResponse:
    return await ProfileService(
        session,
        clock=clock,
        storage=storage,
        settings=settings,
    ).update_me(user, payload)


@router.delete("/me", response_model=AccountDeletionResponse, status_code=202)
async def delete_me(
    response: Response,
    user: User = Depends(get_current_user_allowing_pending_deletion),
    session: AsyncSession = Depends(get_db_session),
    clock: Clock = Depends(get_clock),
    storage: StorageAdapter = Depends(get_storage_adapter),
    settings: Settings = Depends(get_settings),
    idempotency_key: str | None = Header(default=None, alias="Idempotency-Key"),
) -> AccountDeletionResponse:
    body, status_code = await AccountDeletionService(
        session,
        clock,
        settings,
        storage,
    ).request_deletion(user=user, idempotency_key=idempotency_key)
    response.status_code = status_code
    return body


@router.get("/me/preferences", response_model=PreferencesSummary)
async def get_my_preferences(
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db_session),
) -> PreferencesSummary:
    return await PreferencesService(session).get_summary(user.id)


@router.patch("/me/preferences", response_model=PreferencesSummary)
async def update_my_preferences(
    payload: PreferencesUpdateRequest,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db_session),
) -> PreferencesSummary:
    return await PreferencesService(session).update(user.id, payload)
