"""Sketch Session API schemas."""

from __future__ import annotations

from datetime import datetime
from enum import Enum
from typing import Any
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field

from app.models.sketch_session import SketchSession
from app.schemas.me import TimerModeSchema


class SketchSessionStatusSchema(str, Enum):
    active = "active"
    paused = "paused"
    ready_for_photo = "ready_for_photo"
    uploading = "uploading"
    completed = "completed"
    abandoned = "abandoned"
    expired = "expired"


class SketchSessionEventTypeSchema(str, Enum):
    started = "started"
    paused = "paused"
    resumed = "resumed"
    timer_completed = "timer_completed"
    finished_early = "finished_early"
    photo_step_reached = "photo_step_reached"
    upload_started = "upload_started"
    upload_completed = "upload_completed"
    submission_created = "submission_created"
    abandoned = "abandoned"


class CreateSketchSessionRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    prompt_id: UUID
    timer_mode: TimerModeSchema
    selected_timer_seconds: int | None = None
    client_timezone: str | None = None
    client_session_id: str | None = Field(default=None, max_length=128)


class SketchSessionEventRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    event_type: SketchSessionEventTypeSchema
    client_occurred_at: datetime | None = None
    metadata: dict[str, Any] = Field(default_factory=dict)


class SketchSessionResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: UUID
    user_id: UUID
    prompt_id: UUID
    timer_mode: TimerModeSchema
    selected_timer_seconds: int | None
    status: SketchSessionStatusSchema
    started_at: datetime
    paused_total_seconds: int
    timer_completed_at: datetime | None
    finish_requested_at: datetime | None
    photo_step_reached_at: datetime | None
    upload_started_at: datetime | None
    upload_completed_at: datetime | None
    completed_at: datetime | None
    abandoned_at: datetime | None
    created_at: datetime
    updated_at: datetime

    @classmethod
    def from_orm(cls, session: SketchSession) -> SketchSessionResponse:
        return cls(
            id=session.id,
            user_id=session.user_id,
            prompt_id=session.prompt_id,
            timer_mode=TimerModeSchema(session.timer_mode.value),
            selected_timer_seconds=session.selected_timer_seconds,
            status=SketchSessionStatusSchema(session.status.value),
            started_at=session.started_at,
            paused_total_seconds=session.paused_total_seconds,
            timer_completed_at=session.timer_completed_at,
            finish_requested_at=session.finish_requested_at,
            photo_step_reached_at=session.photo_step_reached_at,
            upload_started_at=session.upload_started_at,
            upload_completed_at=session.upload_completed_at,
            completed_at=session.completed_at,
            abandoned_at=session.abandoned_at,
            created_at=session.created_at,
            updated_at=session.updated_at,
        )
