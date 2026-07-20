"""Moderation audit repository."""

from __future__ import annotations

import uuid

from sqlalchemy.ext.asyncio import AsyncSession

from app.models.moderation_action import ModerationAction, ModerationActionType
from app.models.report import ReportTargetType


class ModerationActionRepository:
    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def record(
        self,
        *,
        operator_identity: str,
        action: ModerationActionType,
        target_type: ReportTargetType,
        target_id: uuid.UUID,
        reason: str,
        report_id: uuid.UUID | None = None,
        commit: bool = True,
    ) -> ModerationAction:
        row = ModerationAction(
            id=uuid.uuid4(),
            operator_identity=operator_identity,
            action=action,
            target_type=target_type,
            target_id=target_id,
            reason=reason,
            report_id=report_id,
        )
        self._session.add(row)
        if commit:
            await self._session.commit()
            await self._session.refresh(row)
        else:
            await self._session.flush()
        return row
