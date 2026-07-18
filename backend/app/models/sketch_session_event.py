"""Sketch Session event ORM model."""

from __future__ import annotations

import enum
import uuid
from datetime import datetime
from typing import Any

from sqlalchemy import DateTime, Enum, ForeignKey, Uuid, func
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from app.db.session import Base


class SketchSessionEventType(str, enum.Enum):
    """Sketch Session lifecycle event type."""

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


class SketchSessionEvent(Base):
    """Append-only lifecycle event for a Sketch Session."""

    __tablename__ = "sketch_session_events"

    id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid.uuid4)
    sketch_session_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True),
        ForeignKey("sketch_sessions.id", ondelete="CASCADE"),
        nullable=False,
    )
    event_type: Mapped[SketchSessionEventType] = mapped_column(
        Enum(SketchSessionEventType, name="sketch_session_event_type", native_enum=True),
        nullable=False,
    )
    occurred_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    client_occurred_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )
    metadata_json: Mapped[dict[str, Any]] = mapped_column(
        JSONB,
        nullable=False,
        default=dict,
        server_default="{}",
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )
