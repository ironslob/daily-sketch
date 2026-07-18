"""API schemas for the current-user endpoint."""

from __future__ import annotations

from enum import Enum
from uuid import UUID

from pydantic import BaseModel, ConfigDict

from app.models.user import User


class UserStatusSchema(str, Enum):
    incomplete = "incomplete"
    active = "active"
    suspended = "suspended"
    pending_deletion = "pending_deletion"
    deleted = "deleted"


class TimerModeSchema(str, Enum):
    countdown = "countdown"
    no_timer = "no_timer"


class AppearancePreferenceSchema(str, Enum):
    system = "system"
    light = "light"
    dark = "dark"


class PreferencesSummary(BaseModel):
    """Phase 2 returns defaults; Phase 3 persists preferences."""

    model_config = ConfigDict(extra="forbid")

    notifications_enabled: bool = False
    notification_time_local: str | None = None
    timezone: str = "UTC"
    remember_timer_option: bool = False
    remembered_timer_mode: TimerModeSchema | None = None
    remembered_timer_seconds: int | None = None
    appearance: AppearancePreferenceSchema = AppearancePreferenceSchema.system


class CurrentUserResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: UUID
    username: str | None
    display_name: str
    profile_completed: bool
    status: UserStatusSchema
    preferences: PreferencesSummary

    @classmethod
    def from_user(cls, user: User) -> CurrentUserResponse:
        return cls(
            id=user.id,
            username=user.username,
            display_name=user.display_name,
            profile_completed=user.profile_completed_at is not None,
            status=UserStatusSchema(user.status.value),
            preferences=PreferencesSummary(),
        )
