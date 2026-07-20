"""Reporting application service."""

from __future__ import annotations

import uuid

from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import AppError
from app.models.reflection import ReflectionStatus
from app.models.report import ReportReason, ReportTargetType
from app.models.submission import SubmissionStatus
from app.models.user import User, UserStatus
from app.repositories.reflections import ReflectionRepository
from app.repositories.reports import ReportRepository
from app.repositories.submissions import SubmissionRepository
from app.repositories.users import UserRepository
from app.schemas.safety import CreateReportRequest, ReportResponse

CONFIRMATION_MESSAGE = "Thank you. Your report has been received."


class ReportService:
    def __init__(self, session: AsyncSession) -> None:
        self._session = session
        self._reports = ReportRepository(session)
        self._submissions = SubmissionRepository(session)
        self._reflections = ReflectionRepository(session)
        self._users = UserRepository(session)

    async def create(self, *, reporter: User, payload: CreateReportRequest) -> ReportResponse:
        target_type = ReportTargetType(payload.target_type.value)
        reason = ReportReason(payload.reason.value)
        notes = payload.notes.strip() if payload.notes else None
        if notes == "":
            notes = None
        if reason == ReportReason.other and not notes:
            raise AppError(
                code="report_invalid",
                message="Please add a short note when choosing Other.",
                status_code=422,
            )

        await self._validate_target(target_type=target_type, target_id=payload.target_id)

        existing = await self._reports.find_open(
            reporter_user_id=reporter.id,
            target_type=target_type,
            target_id=payload.target_id,
        )
        if existing is not None:
            return ReportResponse(id=existing.id, message=CONFIRMATION_MESSAGE)

        report = await self._reports.create(
            reporter_user_id=reporter.id,
            target_type=target_type,
            target_id=payload.target_id,
            reason=reason,
            notes=notes,
        )
        return ReportResponse(id=report.id, message=CONFIRMATION_MESSAGE)

    async def _validate_target(
        self,
        *,
        target_type: ReportTargetType,
        target_id: uuid.UUID,
    ) -> None:
        if target_type == ReportTargetType.submission:
            submission = await self._submissions.get_by_id(target_id)
            if (
                submission is None
                or submission.status
                in {
                    SubmissionStatus.deleted,
                    SubmissionStatus.removed,
                }
                or submission.deleted_at is not None
            ):
                raise AppError(
                    code="report_target_not_found",
                    message="The reported content could not be found.",
                    status_code=404,
                )
            return
        if target_type == ReportTargetType.reflection:
            reflection = await self._reflections.get_by_id(target_id)
            if (
                reflection is None
                or reflection.status
                in {
                    ReflectionStatus.deleted,
                    ReflectionStatus.removed,
                }
                or reflection.deleted_at is not None
            ):
                raise AppError(
                    code="report_target_not_found",
                    message="The reported content could not be found.",
                    status_code=404,
                )
            return
        user = await self._users.get_by_id(target_id)
        if (
            user is None
            or user.deleted_at is not None
            or user.status
            not in {
                UserStatus.incomplete,
                UserStatus.active,
                UserStatus.suspended,
            }
        ):
            raise AppError(
                code="report_target_not_found",
                message="The reported profile could not be found.",
                status_code=404,
            )
