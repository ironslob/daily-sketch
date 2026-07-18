"""Sketch Session persistence helpers."""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Any

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.enums import TimerMode
from app.models.sketch_session import SketchSession, SketchSessionStatus
from app.models.sketch_session_event import SketchSessionEvent, SketchSessionEventType


class SketchSessionRepository:
    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def get_by_id(self, session_id: uuid.UUID) -> SketchSession | None:
        result = await self._session.execute(
            select(SketchSession).where(SketchSession.id == session_id)
        )
        return result.scalar_one_or_none()

    async def create_session(
        self,
        *,
        user_id: uuid.UUID,
        prompt_id: uuid.UUID,
        timer_mode: TimerMode,
        selected_timer_seconds: int | None,
        started_at: datetime,
        started_metadata: dict[str, Any] | None = None,
    ) -> SketchSession:
        sketch_session = SketchSession(
            id=uuid.uuid4(),
            user_id=user_id,
            prompt_id=prompt_id,
            timer_mode=timer_mode,
            selected_timer_seconds=selected_timer_seconds,
            status=SketchSessionStatus.active,
            started_at=started_at,
            paused_total_seconds=0,
        )
        self._session.add(sketch_session)
        await self._session.flush()

        started_event = SketchSessionEvent(
            id=uuid.uuid4(),
            sketch_session_id=sketch_session.id,
            event_type=SketchSessionEventType.started,
            occurred_at=started_at,
            client_occurred_at=None,
            metadata_json=started_metadata or {},
        )
        self._session.add(started_event)
        await self._session.commit()
        await self._session.refresh(sketch_session)
        return sketch_session

    async def add_event(
        self,
        *,
        sketch_session: SketchSession,
        event_type: SketchSessionEventType,
        occurred_at: datetime,
        client_occurred_at: datetime | None = None,
        metadata: dict[str, Any] | None = None,
    ) -> SketchSessionEvent:
        event = SketchSessionEvent(
            id=uuid.uuid4(),
            sketch_session_id=sketch_session.id,
            event_type=event_type,
            occurred_at=occurred_at,
            client_occurred_at=client_occurred_at,
            metadata_json=metadata or {},
        )
        self._session.add(event)
        await self._session.flush()
        return event

    async def get_latest_event(
        self,
        *,
        sketch_session_id: uuid.UUID,
        event_type: SketchSessionEventType,
    ) -> SketchSessionEvent | None:
        result = await self._session.execute(
            select(SketchSessionEvent)
            .where(
                SketchSessionEvent.sketch_session_id == sketch_session_id,
                SketchSessionEvent.event_type == event_type,
            )
            .order_by(SketchSessionEvent.occurred_at.desc())
            .limit(1)
        )
        return result.scalar_one_or_none()

    async def save(self, sketch_session: SketchSession) -> SketchSession:
        await self._session.commit()
        await self._session.refresh(sketch_session)
        return sketch_session
