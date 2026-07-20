"""Upload routes."""

from uuid import UUID

from fastapi import APIRouter, Depends, Header, Response
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.deps import get_current_user
from app.core.clock import Clock, get_clock
from app.core.settings import Settings, get_settings
from app.db.session import get_db_session
from app.models.user import User
from app.schemas.uploads import CreateUploadRequest, UploadResponse
from app.services.uploads import UploadService
from app.storage.base import StorageAdapter, get_storage_adapter

router = APIRouter(tags=["uploads"])


@router.post("/uploads", response_model=UploadResponse, status_code=201)
async def create_upload(
    payload: CreateUploadRequest,
    response: Response,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db_session),
    clock: Clock = Depends(get_clock),
    storage: StorageAdapter = Depends(get_storage_adapter),
    settings: Settings = Depends(get_settings),
    idempotency_key: str | None = Header(default=None, alias="Idempotency-Key"),
) -> UploadResponse:
    body, status_code = await UploadService(session, clock, storage, settings).create(
        user=user,
        payload=payload,
        idempotency_key=idempotency_key,
    )
    response.status_code = status_code
    return body


@router.get("/uploads/{upload_id}", response_model=UploadResponse)
async def get_upload(
    upload_id: UUID,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db_session),
    clock: Clock = Depends(get_clock),
    storage: StorageAdapter = Depends(get_storage_adapter),
    settings: Settings = Depends(get_settings),
) -> UploadResponse:
    return await UploadService(session, clock, storage, settings).get(
        user=user,
        upload_id=upload_id,
    )


@router.post("/uploads/{upload_id}/refresh-signed-upload", response_model=UploadResponse)
async def refresh_signed_upload(
    upload_id: UUID,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db_session),
    clock: Clock = Depends(get_clock),
    storage: StorageAdapter = Depends(get_storage_adapter),
    settings: Settings = Depends(get_settings),
) -> UploadResponse:
    return await UploadService(session, clock, storage, settings).refresh_signed_upload(
        user=user,
        upload_id=upload_id,
    )


@router.post("/uploads/{upload_id}/complete", response_model=UploadResponse)
async def complete_upload(
    upload_id: UUID,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db_session),
    clock: Clock = Depends(get_clock),
    storage: StorageAdapter = Depends(get_storage_adapter),
    settings: Settings = Depends(get_settings),
) -> UploadResponse:
    return await UploadService(session, clock, storage, settings).complete(
        user=user,
        upload_id=upload_id,
    )
