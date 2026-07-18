"""Daily Prompt persistence helpers."""

from __future__ import annotations

import uuid
from datetime import date, datetime

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.daily_prompt import DailyPrompt, PromptStatus


class PromptRepository:
    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def get_by_id(self, prompt_id: uuid.UUID) -> DailyPrompt | None:
        result = await self._session.execute(select(DailyPrompt).where(DailyPrompt.id == prompt_id))
        return result.scalar_one_or_none()

    async def get_by_date(self, prompt_date: date) -> DailyPrompt | None:
        result = await self._session.execute(
            select(DailyPrompt).where(DailyPrompt.prompt_date == prompt_date)
        )
        return result.scalar_one_or_none()

    async def get_published_by_date(self, prompt_date: date) -> DailyPrompt | None:
        result = await self._session.execute(
            select(DailyPrompt).where(
                DailyPrompt.prompt_date == prompt_date,
                DailyPrompt.status == PromptStatus.published,
            )
        )
        return result.scalar_one_or_none()

    async def get_published_by_id(self, prompt_id: uuid.UUID) -> DailyPrompt | None:
        result = await self._session.execute(
            select(DailyPrompt).where(
                DailyPrompt.id == prompt_id,
                DailyPrompt.status == PromptStatus.published,
            )
        )
        return result.scalar_one_or_none()

    async def upsert_published(
        self,
        *,
        prompt_date: date,
        word_1: str,
        word_2: str,
        word_3: str,
        published_at: datetime,
    ) -> DailyPrompt:
        existing = await self.get_by_date(prompt_date)
        if existing is not None:
            existing.word_1 = word_1
            existing.word_2 = word_2
            existing.word_3 = word_3
            existing.status = PromptStatus.published
            existing.published_at = published_at
            await self._session.commit()
            await self._session.refresh(existing)
            return existing

        prompt = DailyPrompt(
            id=uuid.uuid4(),
            prompt_date=prompt_date,
            word_1=word_1,
            word_2=word_2,
            word_3=word_3,
            status=PromptStatus.published,
            published_at=published_at,
        )
        self._session.add(prompt)
        await self._session.commit()
        await self._session.refresh(prompt)
        return prompt
