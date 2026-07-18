"""Sketch Session application service."""

from __future__ import annotations

import hashlib
import json
import uuid
from datetime import timedelta
from typing import Any

from sqlalchemy.ext.asyncio import AsyncSession

from app.core.clock import Clock
from app.core.errors import AppError
from app.core.settings import Settings, get_settings
from app.models.enums import TimerMode
from app.models.sketch_session import SketchSession, SketchSessionStatus
from app.models.sketch_session_event import SketchSessionEventType
from app.models.user import User
from app.repositories.idempotency import IdempotencyRepository
from app.repositories.prompts import PromptRepository
from app.repositories.sketch_sessions import SketchSessionRepository
from app.schemas.sketch_sessions import (
    CreateSketchSessionRequest,
    SketchSessionEventRequest,
    SketchSessionEventTypeSchema,
    SketchSessionResponse,
)
from app.services.preferences import ALLOWED_TIMER_SECONDS

CREATE_ENDPOINT = "POST /api/v1/sketch-sessions"

# Phase 5 clients may post these event types. Later upload/submission
# events remain in the contract for forward-compat but are rejected here.
PHASE_5_CLIENT_EVENTS = frozenset(
    {
        SketchSessionEventType.paused,
        SketchSessionEventType.resumed,
        SketchSessionEventType.timer_completed,
        SketchSessionEventType.finished_early,
        SketchSessionEventType.photo_step_reached,
        SketchSessionEventType.abandoned,
    }
)

TERMINAL_STATUSES = frozenset(
    {
        SketchSessionStatus.ready_for_photo,
        SketchSessionStatus.uploading,
        SketchSessionStatus.completed,
        SketchSessionStatus.abandoned,
        SketchSessionStatus.expired,
    }
)


class SketchSessionService:
    def __init__(
        self,
        session: AsyncSession,
        clock: Clock,
        settings: Settings | None = None,
    ) -> None:
        self._sessions = SketchSessionRepository(session)
        self._prompts = PromptRepository(session)
        self._idempotency = IdempotencyRepository(session)
        self._clock = clock
        self._settings = settings or get_settings()

    async def create(
        self,
        *,
        user: User,
        payload: CreateSketchSessionRequest,
        idempotency_key: str | None,
    ) -> tuple[SketchSessionResponse, int]:
        request_hash = _hash_create_request(payload)
        if idempotency_key:
            existing = await self._idempotency.get(
                user_id=user.id,
                endpoint=CREATE_ENDPOINT,
                key=idempotency_key,
            )
            if existing is not None:
                if existing.request_hash != request_hash:
                    raise AppError(
                        code="idempotency_key_conflict",
                        message="This idempotency key was already used with a different request.",
                        status_code=409,
                    )
                return SketchSessionResponse.model_validate(
                    existing.response_body
                ), existing.response_status

        prompt = await self._prompts.get_published_by_id(payload.prompt_id)
        if prompt is None:
            raise AppError(
                code="prompt_not_found",
                message="The requested prompt could not be found.",
                status_code=404,
            )

        timer_mode = TimerMode(payload.timer_mode.value)
        validate_timer_selection(timer_mode, payload.selected_timer_seconds)

        now = self._clock.now()
        metadata: dict[str, Any] = {}
        if payload.client_timezone:
            metadata["client_timezone"] = payload.client_timezone
        if payload.client_session_id:
            metadata["client_session_id"] = payload.client_session_id

        sketch_session = await self._sessions.create_session(
            user_id=user.id,
            prompt_id=payload.prompt_id,
            timer_mode=timer_mode,
            selected_timer_seconds=payload.selected_timer_seconds,
            started_at=now,
            started_metadata=metadata or None,
        )
        response = SketchSessionResponse.from_orm(sketch_session)

        if idempotency_key:
            expires_at = now + timedelta(days=7)
            await self._idempotency.put(
                user_id=user.id,
                endpoint=CREATE_ENDPOINT,
                key=idempotency_key,
                request_hash=request_hash,
                response_status=201,
                response_body=response.model_dump(mode="json"),
                expires_at=expires_at,
            )

        return response, 201

    async def get(self, *, user: User, session_id: uuid.UUID) -> SketchSessionResponse:
        sketch_session = await self._require_owned_session(user=user, session_id=session_id)
        sketch_session = await self._maybe_expire(sketch_session)
        return SketchSessionResponse.from_orm(sketch_session)

    async def record_event(
        self,
        *,
        user: User,
        session_id: uuid.UUID,
        payload: SketchSessionEventRequest,
    ) -> SketchSessionResponse:
        sketch_session = await self._require_owned_session(user=user, session_id=session_id)
        sketch_session = await self._maybe_expire(sketch_session)

        event_type = SketchSessionEventType(payload.event_type.value)
        if event_type not in PHASE_5_CLIENT_EVENTS:
            raise AppError(
                code="invalid_session_transition",
                message="That lifecycle event is not valid for the current session state.",
                status_code=422,
                details={"event_type": event_type.value, "status": sketch_session.status.value},
            )

        if event_type == SketchSessionEventType.abandoned:
            return await self.abandon(user=user, session_id=session_id)

        self._assert_transition_allowed(sketch_session, event_type)

        now = self._clock.now()
        await self._sessions.add_event(
            sketch_session=sketch_session,
            event_type=event_type,
            occurred_at=now,
            client_occurred_at=payload.client_occurred_at,
            metadata=payload.metadata,
        )
        await self._apply_event_side_effects(sketch_session, event_type, now)
        sketch_session = await self._sessions.save(sketch_session)
        return SketchSessionResponse.from_orm(sketch_session)

    async def abandon(self, *, user: User, session_id: uuid.UUID) -> SketchSessionResponse:
        sketch_session = await self._require_owned_session(user=user, session_id=session_id)
        if sketch_session.status == SketchSessionStatus.abandoned:
            return SketchSessionResponse.from_orm(sketch_session)

        if sketch_session.status in {
            SketchSessionStatus.completed,
            SketchSessionStatus.expired,
            SketchSessionStatus.uploading,
        }:
            raise AppError(
                code="invalid_session_transition",
                message="That lifecycle event is not valid for the current session state.",
                status_code=422,
                details={
                    "event_type": SketchSessionEventTypeSchema.abandoned.value,
                    "status": sketch_session.status.value,
                },
            )

        now = self._clock.now()
        await self._sessions.add_event(
            sketch_session=sketch_session,
            event_type=SketchSessionEventType.abandoned,
            occurred_at=now,
        )
        sketch_session.status = SketchSessionStatus.abandoned
        sketch_session.abandoned_at = now
        sketch_session = await self._sessions.save(sketch_session)
        return SketchSessionResponse.from_orm(sketch_session)

    async def _require_owned_session(
        self,
        *,
        user: User,
        session_id: uuid.UUID,
    ) -> SketchSession:
        sketch_session = await self._sessions.get_by_id(session_id)
        if sketch_session is None or sketch_session.user_id != user.id:
            raise AppError(
                code="session_not_found",
                message="The requested sketch session could not be found.",
                status_code=404,
            )
        return sketch_session

    async def _maybe_expire(self, sketch_session: SketchSession) -> SketchSession:
        if sketch_session.status in TERMINAL_STATUSES:
            return sketch_session
        expiry_seconds = self._settings.sketch_session_expiry_seconds
        age = self._clock.now() - sketch_session.started_at
        if age.total_seconds() < expiry_seconds:
            return sketch_session

        sketch_session.status = SketchSessionStatus.expired
        return await self._sessions.save(sketch_session)

    def _assert_transition_allowed(
        self,
        sketch_session: SketchSession,
        event_type: SketchSessionEventType,
    ) -> None:
        status = sketch_session.status
        allowed = False
        if status == SketchSessionStatus.active:
            allowed = event_type in {
                SketchSessionEventType.paused,
                SketchSessionEventType.timer_completed,
                SketchSessionEventType.finished_early,
                SketchSessionEventType.photo_step_reached,
            }
            if event_type == SketchSessionEventType.timer_completed:
                allowed = sketch_session.timer_mode == TimerMode.countdown
        elif status == SketchSessionStatus.paused:
            allowed = event_type == SketchSessionEventType.resumed

        if not allowed:
            raise AppError(
                code="invalid_session_transition",
                message="That lifecycle event is not valid for the current session state.",
                status_code=422,
                details={"event_type": event_type.value, "status": status.value},
            )

    async def _apply_event_side_effects(
        self,
        sketch_session: SketchSession,
        event_type: SketchSessionEventType,
        now: Any,
    ) -> None:
        if event_type == SketchSessionEventType.paused:
            sketch_session.status = SketchSessionStatus.paused
            return

        if event_type == SketchSessionEventType.resumed:
            paused_event = await self._sessions.get_latest_event(
                sketch_session_id=sketch_session.id,
                event_type=SketchSessionEventType.paused,
            )
            if paused_event is not None:
                delta = int((now - paused_event.occurred_at).total_seconds())
                if delta > 0:
                    sketch_session.paused_total_seconds += delta
            sketch_session.status = SketchSessionStatus.active
            return

        if event_type == SketchSessionEventType.timer_completed:
            sketch_session.timer_completed_at = now
            sketch_session.status = SketchSessionStatus.ready_for_photo
            return

        if event_type == SketchSessionEventType.finished_early:
            sketch_session.finish_requested_at = now
            sketch_session.status = SketchSessionStatus.ready_for_photo
            return

        if event_type == SketchSessionEventType.photo_step_reached:
            sketch_session.photo_step_reached_at = now
            sketch_session.status = SketchSessionStatus.ready_for_photo


def validate_timer_selection(mode: TimerMode, seconds: int | None) -> None:
    """Validate Sketch Session timer mode/seconds combination."""
    if mode == TimerMode.no_timer:
        if seconds is not None:
            raise AppError(
                code="invalid_timer_selection",
                message="Timer mode and selected seconds are inconsistent.",
                status_code=422,
            )
        return
    if mode == TimerMode.countdown:
        if seconds not in ALLOWED_TIMER_SECONDS:
            raise AppError(
                code="invalid_timer_selection",
                message="Timer mode and selected seconds are inconsistent.",
                status_code=422,
            )
        return
    raise AppError(
        code="invalid_timer_selection",
        message="Timer mode and selected seconds are inconsistent.",
        status_code=422,
    )


def _hash_create_request(payload: CreateSketchSessionRequest) -> str:
    canonical = json.dumps(payload.model_dump(mode="json"), sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()
