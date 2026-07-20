"""Moderation audit ORM model."""

from __future__ import annotations

import enum
import uuid
from datetime import datetime

from sqlalchemy import DateTime, Enum, ForeignKey, Text, Uuid, func
from sqlalchemy.orm import Mapped, mapped_column

from app.db.session import Base
from app.models.report import ReportTargetType


class ModerationActionType(str, enum.Enum):
    """Operator moderation action kinds."""

    hide_submission = "hide_submission"
    remove_submission = "remove_submission"
    restore_submission = "restore_submission"
    hide_reflection = "hide_reflection"
    remove_reflection = "remove_reflection"
    restore_reflection = "restore_reflection"
    suspend_user = "suspend_user"
    restore_user = "restore_user"
    resolve_report = "resolve_report"
    dismiss_report = "dismiss_report"


class ModerationAction(Base):
    """Immutable audit row for an operator moderation action."""

    __tablename__ = "moderation_actions"

    id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid.uuid4)
    operator_identity: Mapped[str] = mapped_column(Text, nullable=False)
    action: Mapped[ModerationActionType] = mapped_column(
        Enum(ModerationActionType, name="moderation_action_type", native_enum=True),
        nullable=False,
    )
    target_type: Mapped[ReportTargetType] = mapped_column(
        Enum(ReportTargetType, name="report_target_type", native_enum=True, create_type=False),
        nullable=False,
    )
    target_id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), nullable=False)
    reason: Mapped[str] = mapped_column(Text, nullable=False)
    report_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid(as_uuid=True),
        ForeignKey("reports.id", ondelete="SET NULL"),
        nullable=True,
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )
