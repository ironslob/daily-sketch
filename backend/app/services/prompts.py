"""Daily Prompt application service."""

from __future__ import annotations

import uuid

from sqlalchemy.ext.asyncio import AsyncSession

from app.core.clock import Clock
from app.core.errors import AppError
from app.repositories.prompts import PromptRepository
from app.schemas.prompts import DailyPromptResponse


class PromptService:
    def __init__(self, session: AsyncSession, clock: Clock) -> None:
        self._prompts = PromptRepository(session)
        self._clock = clock

    async def get_today(self) -> DailyPromptResponse:
        prompt = await self._prompts.get_published_by_date(self._clock.today())
        if prompt is None:
            raise AppError(
                code="prompt_not_found",
                message="Today's prompt is not available yet.",
                status_code=404,
            )
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
