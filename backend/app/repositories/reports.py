"""Report repository."""

from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.report import Report, ReportReason, ReportStatus, ReportTargetType


class ReportRepository:
    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def get_by_id(self, report_id: uuid.UUID) -> Report | None:
        result = await self._session.execute(select(Report).where(Report.id == report_id))
        return result.scalar_one_or_none()

    async def find_open(
        self,
        *,
        reporter_user_id: uuid.UUID,
        target_type: ReportTargetType,
        target_id: uuid.UUID,
    ) -> Report | None:
        result = await self._session.execute(
            select(Report).where(
                Report.reporter_user_id == reporter_user_id,
                Report.target_type == target_type,
                Report.target_id == target_id,
                Report.status == ReportStatus.open,
            )
        )
        return result.scalar_one_or_none()

    async def create(
        self,
        *,
        reporter_user_id: uuid.UUID,
        target_type: ReportTargetType,
        target_id: uuid.UUID,
        reason: ReportReason,
        notes: str | None,
        commit: bool = True,
    ) -> Report:
        report = Report(
            id=uuid.uuid4(),
            reporter_user_id=reporter_user_id,
            target_type=target_type,
            target_id=target_id,
            reason=reason,
            notes=notes,
            status=ReportStatus.open,
        )
        self._session.add(report)
        if commit:
            await self._session.commit()
            await self._session.refresh(report)
        else:
            await self._session.flush()
        return report

    async def list_open(self, *, limit: int = 50) -> list[Report]:
        result = await self._session.execute(
            select(Report)
            .where(Report.status == ReportStatus.open)
            .order_by(Report.created_at.asc())
            .limit(limit)
        )
        return list(result.scalars().all())

    async def mark_reviewed(
        self,
        report: Report,
        *,
        status: ReportStatus,
        reviewed_at: datetime,
        reviewed_by_user_id: uuid.UUID | None,
        resolution_notes: str | None,
        commit: bool = True,
    ) -> Report:
        report.status = status
        report.reviewed_at = reviewed_at
        report.reviewed_by_user_id = reviewed_by_user_id
        report.resolution_notes = resolution_notes
        if commit:
            await self._session.commit()
            await self._session.refresh(report)
        else:
            await self._session.flush()
        return report
