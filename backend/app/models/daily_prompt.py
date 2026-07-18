"""Daily Prompt ORM model."""

from __future__ import annotations

import enum
import uuid
from datetime import date, datetime

from sqlalchemy import Date, DateTime, Enum, Text, UniqueConstraint, Uuid, func
from sqlalchemy.orm import Mapped, mapped_column

from app.db.session import Base


class PromptStatus(str, enum.Enum):
    """Daily Prompt publication lifecycle status."""

    draft = "draft"
    published = "published"
    withdrawn = "withdrawn"


class DailyPrompt(Base):
    """Shared three-word Daily Prompt for one Prompt Date."""

    __tablename__ = "daily_prompts"
    __table_args__ = (UniqueConstraint("prompt_date", name="uq_daily_prompts_prompt_date"),)

    id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid.uuid4)
    prompt_date: Mapped[date] = mapped_column(Date, nullable=False)
    word_1: Mapped[str] = mapped_column(Text, nullable=False)
    word_2: Mapped[str] = mapped_column(Text, nullable=False)
    word_3: Mapped[str] = mapped_column(Text, nullable=False)
    status: Mapped[PromptStatus] = mapped_column(
        Enum(PromptStatus, name="prompt_status", native_enum=True),
        nullable=False,
        default=PromptStatus.draft,
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )
    published_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    corrected_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
