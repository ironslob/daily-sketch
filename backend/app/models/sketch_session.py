"""Sketch Session ORM model."""

from __future__ import annotations

import enum
import uuid
from datetime import datetime

from sqlalchemy import DateTime, Enum, ForeignKey, Integer, Uuid, func
from sqlalchemy.orm import Mapped, mapped_column

from app.db.session import Base
from app.models.enums import TimerMode, timer_mode_sa


class SketchSessionStatus(str, enum.Enum):
    """Sketch Session lifecycle status."""

    active = "active"
    paused = "paused"
    ready_for_photo = "ready_for_photo"
    uploading = "uploading"
    completed = "completed"
    abandoned = "abandoned"
    expired = "expired"


class SketchSession(Base):
    """Authenticated Sketch Session for one prompt and timer choice."""

    __tablename__ = "sketch_sessions"

    id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    prompt_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True),
        ForeignKey("daily_prompts.id", ondelete="RESTRICT"),
        nullable=False,
    )
    timer_mode: Mapped[TimerMode] = mapped_column(timer_mode_sa, nullable=False)
    selected_timer_seconds: Mapped[int | None] = mapped_column(Integer, nullable=True)
    status: Mapped[SketchSessionStatus] = mapped_column(
        Enum(SketchSessionStatus, name="sketch_session_status", native_enum=True),
        nullable=False,
        default=SketchSessionStatus.active,
    )
    started_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    paused_total_seconds: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    timer_completed_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )
    finish_requested_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )
    photo_step_reached_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )
    upload_started_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )
    upload_completed_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    abandoned_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
        onupdate=func.now(),
    )
