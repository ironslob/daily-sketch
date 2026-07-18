"""Sketch Session routes."""

from uuid import UUID

from fastapi import APIRouter, Depends, Header, Response
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.deps import get_current_user
from app.core.clock import Clock, get_clock
from app.db.session import get_db_session
from app.models.user import User
from app.schemas.sketch_sessions import (
    CreateSketchSessionRequest,
    SketchSessionEventRequest,
    SketchSessionResponse,
)
from app.services.sketch_sessions import SketchSessionService

router = APIRouter(tags=["sketch-sessions"])


@router.post("/sketch-sessions", response_model=SketchSessionResponse, status_code=201)
async def create_sketch_session(
    payload: CreateSketchSessionRequest,
    response: Response,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db_session),
    clock: Clock = Depends(get_clock),
    idempotency_key: str | None = Header(default=None, alias="Idempotency-Key"),
) -> SketchSessionResponse:
    body, status_code = await SketchSessionService(session, clock).create(
        user=user,
        payload=payload,
        idempotency_key=idempotency_key,
    )
    response.status_code = status_code
    return body


@router.get("/sketch-sessions/{session_id}", response_model=SketchSessionResponse)
async def get_sketch_session(
    session_id: UUID,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db_session),
    clock: Clock = Depends(get_clock),
) -> SketchSessionResponse:
    return await SketchSessionService(session, clock).get(user=user, session_id=session_id)


@router.post(
    "/sketch-sessions/{session_id}/events",
    response_model=SketchSessionResponse,
)
async def post_sketch_session_event(
    session_id: UUID,
    payload: SketchSessionEventRequest,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db_session),
    clock: Clock = Depends(get_clock),
) -> SketchSessionResponse:
    return await SketchSessionService(session, clock).record_event(
        user=user,
        session_id=session_id,
        payload=payload,
    )


@router.post(
    "/sketch-sessions/{session_id}/abandon",
    response_model=SketchSessionResponse,
)
async def abandon_sketch_session(
    session_id: UUID,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db_session),
    clock: Clock = Depends(get_clock),
) -> SketchSessionResponse:
    return await SketchSessionService(session, clock).abandon(user=user, session_id=session_id)
