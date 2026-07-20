"""Internal operator moderation endpoints (not part of the public OpenAPI contract)."""

from __future__ import annotations

from typing import Annotated, Any
from uuid import UUID

from fastapi import APIRouter, Depends, Header
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.clock import Clock, get_clock
from app.core.errors import AppError
from app.core.settings import Settings, get_settings
from app.db.session import get_db_session
from app.models.report import ReportTargetType
from app.services.moderation import ModerationService

router = APIRouter(prefix="/internal/moderation", tags=["moderation"])


class ModerationActionRequest(BaseModel):
    reason: str = Field(min_length=1, max_length=2000)
    report_id: UUID | None = None


class ResolveReportRequest(BaseModel):
    resolution_notes: str = Field(min_length=1, max_length=2000)
    dismiss: bool = False


def require_moderation_operator(
    settings: Settings = Depends(get_settings),
    x_moderation_token: Annotated[str | None, Header(alias="X-Moderation-Token")] = None,
) -> str:
    expected = settings.moderation_operator_token
    if not expected or not x_moderation_token or x_moderation_token != expected:
        raise AppError(
            code="moderation_forbidden",
            message="Moderation access is not permitted.",
            status_code=403,
        )
    return "operator"


@router.get("/reports")
async def list_reports(
    _operator: str = Depends(require_moderation_operator),
    session: AsyncSession = Depends(get_db_session),
    clock: Clock = Depends(get_clock),
    limit: int = 50,
) -> dict[str, Any]:
    items = await ModerationService(session, clock).list_open_reports(limit=limit)
    return {"items": items}


@router.get("/targets/{target_type}/{target_id}")
async def inspect_target(
    target_type: ReportTargetType,
    target_id: UUID,
    _operator: str = Depends(require_moderation_operator),
    session: AsyncSession = Depends(get_db_session),
    clock: Clock = Depends(get_clock),
) -> dict[str, Any]:
    return await ModerationService(session, clock).inspect_target(
        target_type=target_type,
        target_id=target_id,
    )


@router.post("/submissions/{submission_id}/hide")
async def hide_submission(
    submission_id: UUID,
    payload: ModerationActionRequest,
    operator: str = Depends(require_moderation_operator),
    session: AsyncSession = Depends(get_db_session),
    clock: Clock = Depends(get_clock),
) -> dict[str, Any]:
    return await ModerationService(session, clock).hide_submission(
        operator_identity=operator,
        submission_id=submission_id,
        reason=payload.reason,
        report_id=payload.report_id,
    )


@router.post("/submissions/{submission_id}/remove")
async def remove_submission(
    submission_id: UUID,
    payload: ModerationActionRequest,
    operator: str = Depends(require_moderation_operator),
    session: AsyncSession = Depends(get_db_session),
    clock: Clock = Depends(get_clock),
) -> dict[str, Any]:
    return await ModerationService(session, clock).remove_submission(
        operator_identity=operator,
        submission_id=submission_id,
        reason=payload.reason,
        report_id=payload.report_id,
    )


@router.post("/submissions/{submission_id}/restore")
async def restore_submission(
    submission_id: UUID,
    payload: ModerationActionRequest,
    operator: str = Depends(require_moderation_operator),
    session: AsyncSession = Depends(get_db_session),
    clock: Clock = Depends(get_clock),
) -> dict[str, Any]:
    return await ModerationService(session, clock).restore_submission(
        operator_identity=operator,
        submission_id=submission_id,
        reason=payload.reason,
        report_id=payload.report_id,
    )


@router.post("/reflections/{reflection_id}/hide")
async def hide_reflection(
    reflection_id: UUID,
    payload: ModerationActionRequest,
    operator: str = Depends(require_moderation_operator),
    session: AsyncSession = Depends(get_db_session),
    clock: Clock = Depends(get_clock),
) -> dict[str, Any]:
    return await ModerationService(session, clock).hide_reflection(
        operator_identity=operator,
        reflection_id=reflection_id,
        reason=payload.reason,
        report_id=payload.report_id,
    )


@router.post("/reflections/{reflection_id}/remove")
async def remove_reflection(
    reflection_id: UUID,
    payload: ModerationActionRequest,
    operator: str = Depends(require_moderation_operator),
    session: AsyncSession = Depends(get_db_session),
    clock: Clock = Depends(get_clock),
) -> dict[str, Any]:
    return await ModerationService(session, clock).remove_reflection(
        operator_identity=operator,
        reflection_id=reflection_id,
        reason=payload.reason,
        report_id=payload.report_id,
    )


@router.post("/reflections/{reflection_id}/restore")
async def restore_reflection(
    reflection_id: UUID,
    payload: ModerationActionRequest,
    operator: str = Depends(require_moderation_operator),
    session: AsyncSession = Depends(get_db_session),
    clock: Clock = Depends(get_clock),
) -> dict[str, Any]:
    return await ModerationService(session, clock).restore_reflection(
        operator_identity=operator,
        reflection_id=reflection_id,
        reason=payload.reason,
        report_id=payload.report_id,
    )


@router.post("/users/{user_id}/suspend")
async def suspend_user(
    user_id: UUID,
    payload: ModerationActionRequest,
    operator: str = Depends(require_moderation_operator),
    session: AsyncSession = Depends(get_db_session),
    clock: Clock = Depends(get_clock),
) -> dict[str, Any]:
    return await ModerationService(session, clock).suspend_user(
        operator_identity=operator,
        user_id=user_id,
        reason=payload.reason,
        report_id=payload.report_id,
    )


@router.post("/users/{user_id}/restore")
async def restore_user(
    user_id: UUID,
    payload: ModerationActionRequest,
    operator: str = Depends(require_moderation_operator),
    session: AsyncSession = Depends(get_db_session),
    clock: Clock = Depends(get_clock),
) -> dict[str, Any]:
    return await ModerationService(session, clock).restore_user(
        operator_identity=operator,
        user_id=user_id,
        reason=payload.reason,
        report_id=payload.report_id,
    )


@router.post("/reports/{report_id}/resolve")
async def resolve_report(
    report_id: UUID,
    payload: ResolveReportRequest,
    operator: str = Depends(require_moderation_operator),
    session: AsyncSession = Depends(get_db_session),
    clock: Clock = Depends(get_clock),
) -> dict[str, Any]:
    return await ModerationService(session, clock).resolve_report(
        operator_identity=operator,
        report_id=report_id,
        resolution_notes=payload.resolution_notes,
        dismiss=payload.dismiss,
    )
