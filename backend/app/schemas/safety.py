"""Safety, blocking, reporting, and account-deletion API schemas."""

from __future__ import annotations

from enum import Enum
from uuid import UUID

from pydantic import BaseModel, Field


class ReportTargetTypeSchema(str, Enum):
    submission = "submission"
    reflection = "reflection"
    profile = "profile"


class ReportReasonSchema(str, Enum):
    inappropriate = "inappropriate"
    harassment = "harassment"
    hate = "hate"
    spam = "spam"
    intellectual_property = "intellectual_property"
    self_harm = "self_harm"
    other = "other"


class CreateReportRequest(BaseModel):
    target_type: ReportTargetTypeSchema
    target_id: UUID
    reason: ReportReasonSchema
    notes: str | None = Field(default=None, max_length=1000)


class ReportResponse(BaseModel):
    id: UUID
    message: str


class BlockState(BaseModel):
    blocked: bool
    user_id: UUID


class BlockedUserSummary(BaseModel):
    user_id: UUID
    username: str
    display_name: str
    avatar_url: str | None = None


class BlockedUsersResponse(BaseModel):
    items: list[BlockedUserSummary]


class AccountDeletionStatus(str, Enum):
    pending_deletion = "pending_deletion"


class AccountDeletionResponse(BaseModel):
    status: AccountDeletionStatus
    message: str
