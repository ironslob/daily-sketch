"""User preferences ORM model."""

from __future__ import annotations

import enum
import uuid
from datetime import datetime, time

from sqlalchemy import Boolean, DateTime, Enum, ForeignKey, Integer, Text, Time, Uuid, func
from sqlalchemy.orm import Mapped, mapped_column

from app.db.session import Base
from app.models.enums import TimerMode, timer_mode_sa

__all__ = [
    "AppearancePreference",
    "TimerMode",
    "UserPreferences",
]


class AppearancePreference(str, enum.Enum):
    """Preferred colour appearance."""

    system = "system"
    light = "light"
    dark = "dark"


class UserPreferences(Base):
    """Server-backed preferences for an authenticated user."""

    __tablename__ = "user_preferences"

    user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        primary_key=True,
    )
    notifications_enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    notification_time_local: Mapped[time | None] = mapped_column(Time, nullable=True)
    timezone: Mapped[str] = mapped_column(Text, nullable=False, default="UTC")
    remember_timer_option: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    remembered_timer_mode: Mapped[TimerMode | None] = mapped_column(
        timer_mode_sa,
        nullable=True,
    )
    remembered_timer_seconds: Mapped[int | None] = mapped_column(Integer, nullable=True)
    appearance: Mapped[AppearancePreference] = mapped_column(
        Enum(AppearancePreference, name="appearance", native_enum=True),
        nullable=False,
        default=AppearancePreference.system,
    )
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
