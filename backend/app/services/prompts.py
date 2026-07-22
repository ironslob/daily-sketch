"""Daily Prompt application service."""

from __future__ import annotations

import uuid
from datetime import date

from sqlalchemy.ext.asyncio import AsyncSession

from app.core.clock import Clock
from app.core.errors import AppError
from app.models.daily_prompt import DailyPrompt, PromptStatus
from app.repositories.prompts import PromptRepository
from app.schemas.prompts import DailyPromptResponse
from app.seeds.prompts import generate_prompt_words


class PromptService:
    def __init__(self, session: AsyncSession, clock: Clock) -> None:
        self._prompts = PromptRepository(session)
        self._clock = clock

    async def get_today(self) -> DailyPromptResponse:
        prompt = await self.ensure_published(self._clock.today())
        return DailyPromptResponse.from_orm(prompt)

    async def get_by_id(self, prompt_id: uuid.UUID) -> DailyPromptResponse:
        prompt = await self._prompts.get_published_by_id(prompt_id)
        if prompt is None:
            raise AppError(
                code="prompt_not_found",
                message="The requested prompt could not be found.",
                status_code=404,
            )
        return DailyPromptResponse.from_orm(prompt)

    async def ensure_published(self, prompt_date: date) -> DailyPrompt:
        """Return the published prompt for ``prompt_date``, creating it if absent.

        Concurrent callers serialize on a transaction-scoped advisory lock keyed
        by Prompt Date. Existing draft/withdrawn rows are not overwritten.
        """
        existing = await self._prompts.get_published_by_date(prompt_date)
        if existing is not None:
            return existing

        await self._prompts.acquire_prompt_date_lock(prompt_date)

        existing = await self._prompts.get_by_date(prompt_date)
        if existing is not None:
            if existing.status == PromptStatus.published:
                return existing
            raise AppError(
                code="prompt_not_found",
                message="Today's prompt is not available yet.",
                status_code=404,
                details={"prompt_date": prompt_date.isoformat()},
            )

        word_1, word_2, word_3 = generate_prompt_words(prompt_date)
        return await self._prompts.upsert_published(
            prompt_date=prompt_date,
            word_1=word_1,
            word_2=word_2,
            word_3=word_3,
            published_at=self._clock.now(),
        )
