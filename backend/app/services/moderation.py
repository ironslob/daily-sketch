"""Operator moderation service (internal only)."""

from __future__ import annotations

import uuid
from typing import Any

from sqlalchemy.ext.asyncio import AsyncSession

from app.core.clock import Clock
from app.core.errors import AppError
from app.models.moderation_action import ModerationActionType
from app.models.reflection import ReflectionStatus
from app.models.report import ReportStatus, ReportTargetType
from app.models.submission import SubmissionStatus
from app.models.user import UserStatus
from app.repositories.moderation_actions import ModerationActionRepository
from app.repositories.reflections import ReflectionRepository
from app.repositories.reports import ReportRepository
from app.repositories.submissions import SubmissionRepository
from app.repositories.users import UserRepository


class ModerationService:
    def __init__(self, session: AsyncSession, clock: Clock) -> None:
        self._session = session
        self._clock = clock
        self._reports = ReportRepository(session)
        self._actions = ModerationActionRepository(session)
        self._submissions = SubmissionRepository(session)
        self._reflections = ReflectionRepository(session)
        self._users = UserRepository(session)

    async def list_open_reports(self, *, limit: int = 50) -> list[dict[str, Any]]:
        reports = await self._reports.list_open(limit=limit)
        return [
            {
                "id": str(report.id),
                "reporter_user_id": str(report.reporter_user_id),
                "target_type": report.target_type.value,
                "target_id": str(report.target_id),
                "reason": report.reason.value,
                "notes": report.notes,
                "status": report.status.value,
                "created_at": report.created_at.isoformat(),
            }
            for report in reports
        ]

    async def inspect_target(
        self,
        *,
        target_type: ReportTargetType,
        target_id: uuid.UUID,
    ) -> dict[str, Any]:
        if target_type == ReportTargetType.submission:
            submission = await self._submissions.get_by_id(target_id)
            if submission is None:
                raise AppError(
                    code="report_target_not_found",
                    message="The requested target could not be found.",
                    status_code=404,
                )
            return {
                "target_type": "submission",
                "id": str(submission.id),
                "user_id": str(submission.user_id),
                "status": submission.status.value,
                "caption": submission.caption,
                "published_at": submission.published_at.isoformat(),
                "deleted_at": (
                    submission.deleted_at.isoformat() if submission.deleted_at else None
                ),
            }
        if target_type == ReportTargetType.reflection:
            reflection = await self._reflections.get_by_id(target_id)
            if reflection is None:
                raise AppError(
                    code="report_target_not_found",
                    message="The requested target could not be found.",
                    status_code=404,
                )
            return {
                "target_type": "reflection",
                "id": str(reflection.id),
                "submission_id": str(reflection.submission_id),
                "user_id": str(reflection.user_id),
                "status": reflection.status.value,
                "body": reflection.body,
                "created_at": reflection.created_at.isoformat(),
            }
        user = await self._users.get_by_id(target_id)
        if user is None:
            raise AppError(
                code="report_target_not_found",
                message="The requested target could not be found.",
                status_code=404,
            )
        return {
            "target_type": "profile",
            "id": str(user.id),
            "username": user.username,
            "display_name": user.display_name,
            "status": user.status.value,
            "deleted_at": user.deleted_at.isoformat() if user.deleted_at else None,
        }

    async def hide_submission(
        self,
        *,
        operator_identity: str,
        submission_id: uuid.UUID,
        reason: str,
        report_id: uuid.UUID | None = None,
    ) -> dict[str, Any]:
        return await self._set_submission_status(
            operator_identity=operator_identity,
            submission_id=submission_id,
            status=SubmissionStatus.hidden,
            action=ModerationActionType.hide_submission,
            reason=reason,
            report_id=report_id,
        )

    async def remove_submission(
        self,
        *,
        operator_identity: str,
        submission_id: uuid.UUID,
        reason: str,
        report_id: uuid.UUID | None = None,
    ) -> dict[str, Any]:
        return await self._set_submission_status(
            operator_identity=operator_identity,
            submission_id=submission_id,
            status=SubmissionStatus.removed,
            action=ModerationActionType.remove_submission,
            reason=reason,
            report_id=report_id,
        )

    async def restore_submission(
        self,
        *,
        operator_identity: str,
        submission_id: uuid.UUID,
        reason: str,
        report_id: uuid.UUID | None = None,
    ) -> dict[str, Any]:
        return await self._set_submission_status(
            operator_identity=operator_identity,
            submission_id=submission_id,
            status=SubmissionStatus.published,
            action=ModerationActionType.restore_submission,
            reason=reason,
            report_id=report_id,
            clear_deleted_at=True,
        )

    async def hide_reflection(
        self,
        *,
        operator_identity: str,
        reflection_id: uuid.UUID,
        reason: str,
        report_id: uuid.UUID | None = None,
    ) -> dict[str, Any]:
        return await self._set_reflection_status(
            operator_identity=operator_identity,
            reflection_id=reflection_id,
            status=ReflectionStatus.hidden,
            action=ModerationActionType.hide_reflection,
            reason=reason,
            report_id=report_id,
            adjust_counter=-1,
        )

    async def remove_reflection(
        self,
        *,
        operator_identity: str,
        reflection_id: uuid.UUID,
        reason: str,
        report_id: uuid.UUID | None = None,
    ) -> dict[str, Any]:
        return await self._set_reflection_status(
            operator_identity=operator_identity,
            reflection_id=reflection_id,
            status=ReflectionStatus.removed,
            action=ModerationActionType.remove_reflection,
            reason=reason,
            report_id=report_id,
            adjust_counter=-1,
        )

    async def restore_reflection(
        self,
        *,
        operator_identity: str,
        reflection_id: uuid.UUID,
        reason: str,
        report_id: uuid.UUID | None = None,
    ) -> dict[str, Any]:
        return await self._set_reflection_status(
            operator_identity=operator_identity,
            reflection_id=reflection_id,
            status=ReflectionStatus.published,
            action=ModerationActionType.restore_reflection,
            reason=reason,
            report_id=report_id,
            adjust_counter=1,
            clear_deleted_at=True,
        )

    async def suspend_user(
        self,
        *,
        operator_identity: str,
        user_id: uuid.UUID,
        reason: str,
        report_id: uuid.UUID | None = None,
    ) -> dict[str, Any]:
        user = await self._users.get_by_id(user_id)
        if user is None:
            raise AppError(
                code="user_not_found",
                message="The requested user could not be found.",
                status_code=404,
            )
        await self._users.set_status(user, status=UserStatus.suspended, commit=False)
        await self._actions.record(
            operator_identity=operator_identity,
            action=ModerationActionType.suspend_user,
            target_type=ReportTargetType.profile,
            target_id=user_id,
            reason=reason,
            report_id=report_id,
            commit=False,
        )
        await self._session.commit()
        return {"user_id": str(user_id), "status": UserStatus.suspended.value}

    async def restore_user(
        self,
        *,
        operator_identity: str,
        user_id: uuid.UUID,
        reason: str,
        report_id: uuid.UUID | None = None,
    ) -> dict[str, Any]:
        user = await self._users.get_by_id(user_id)
        if user is None:
            raise AppError(
                code="user_not_found",
                message="The requested user could not be found.",
                status_code=404,
            )
        new_status = (
            UserStatus.active if user.profile_completed_at is not None else UserStatus.incomplete
        )
        await self._users.set_status(user, status=new_status, commit=False)
        await self._actions.record(
            operator_identity=operator_identity,
            action=ModerationActionType.restore_user,
            target_type=ReportTargetType.profile,
            target_id=user_id,
            reason=reason,
            report_id=report_id,
            commit=False,
        )
        await self._session.commit()
        return {"user_id": str(user_id), "status": new_status.value}

    async def resolve_report(
        self,
        *,
        operator_identity: str,
        report_id: uuid.UUID,
        resolution_notes: str,
        dismiss: bool = False,
    ) -> dict[str, Any]:
        report = await self._reports.get_by_id(report_id)
        if report is None:
            raise AppError(
                code="report_target_not_found",
                message="The requested report could not be found.",
                status_code=404,
            )
        status = ReportStatus.dismissed if dismiss else ReportStatus.resolved
        action = (
            ModerationActionType.dismiss_report if dismiss else ModerationActionType.resolve_report
        )
        await self._reports.mark_reviewed(
            report,
            status=status,
            reviewed_at=self._clock.now(),
            reviewed_by_user_id=None,
            resolution_notes=resolution_notes,
            commit=False,
        )
        await self._actions.record(
            operator_identity=operator_identity,
            action=action,
            target_type=report.target_type,
            target_id=report.target_id,
            reason=resolution_notes,
            report_id=report.id,
            commit=False,
        )
        await self._session.commit()
        return {"report_id": str(report.id), "status": status.value}

    async def _set_submission_status(
        self,
        *,
        operator_identity: str,
        submission_id: uuid.UUID,
        status: SubmissionStatus,
        action: ModerationActionType,
        reason: str,
        report_id: uuid.UUID | None,
        clear_deleted_at: bool = False,
    ) -> dict[str, Any]:
        submission = await self._submissions.get_by_id(submission_id)
        if submission is None:
            raise AppError(
                code="submission_not_found",
                message="The requested sketch could not be found.",
                status_code=404,
            )
        deleted_at = None if clear_deleted_at else submission.deleted_at
        await self._submissions.set_status(
            submission,
            status=status,
            deleted_at=deleted_at,
            commit=False,
        )
        await self._actions.record(
            operator_identity=operator_identity,
            action=action,
            target_type=ReportTargetType.submission,
            target_id=submission_id,
            reason=reason,
            report_id=report_id,
            commit=False,
        )
        await self._session.commit()
        return {"submission_id": str(submission_id), "status": status.value}

    async def _set_reflection_status(
        self,
        *,
        operator_identity: str,
        reflection_id: uuid.UUID,
        status: ReflectionStatus,
        action: ModerationActionType,
        reason: str,
        report_id: uuid.UUID | None,
        adjust_counter: int = 0,
        clear_deleted_at: bool = False,
    ) -> dict[str, Any]:
        reflection = await self._reflections.get_by_id(reflection_id)
        if reflection is None:
            raise AppError(
                code="reflection_not_found",
                message="The requested reflection could not be found.",
                status_code=404,
            )
        previous = reflection.status
        deleted_at = None if clear_deleted_at else reflection.deleted_at
        await self._reflections.set_moderation_status(
            reflection,
            status=status,
            deleted_at=deleted_at,
            commit=False,
        )
        if adjust_counter and previous != status:
            submission = await self._submissions.get_by_id(reflection.submission_id)
            if submission is not None:
                if adjust_counter < 0 and previous == ReflectionStatus.published:
                    submission.reflection_count = max(0, submission.reflection_count - 1)
                elif adjust_counter > 0 and status == ReflectionStatus.published:
                    submission.reflection_count = submission.reflection_count + 1
        await self._actions.record(
            operator_identity=operator_identity,
            action=action,
            target_type=ReportTargetType.reflection,
            target_id=reflection_id,
            reason=reason,
            report_id=report_id,
            commit=False,
        )
        await self._session.commit()
        return {"reflection_id": str(reflection_id), "status": status.value}
