"""Shared ORM enums and SQLAlchemy enum type bindings."""

from __future__ import annotations

import enum

from sqlalchemy import Enum


class TimerMode(str, enum.Enum):
    """Remembered Sketch Session timer mode."""

    countdown = "countdown"
    no_timer = "no_timer"


# Single shared Postgres enum type so create_all / multiple models do not
# attempt to CREATE TYPE timer_mode more than once.
timer_mode_sa = Enum(TimerMode, name="timer_mode", native_enum=True)
