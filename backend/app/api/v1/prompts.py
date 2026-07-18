"""Daily Prompt routes."""

from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.clock import Clock, get_clock
from app.db.session import get_db_session
from app.schemas.prompts import DailyPromptResponse
from app.services.prompts import PromptService

router = APIRouter(tags=["prompts"])


@router.get("/prompts/today", response_model=DailyPromptResponse)
async def get_todays_prompt(
    session: AsyncSession = Depends(get_db_session),
    clock: Clock = Depends(get_clock),
) -> DailyPromptResponse:
    return await PromptService(session, clock).get_today()


@router.get("/prompts/{prompt_id}", response_model=DailyPromptResponse)
async def get_prompt_by_id(
    prompt_id: uuid.UUID,
    session: AsyncSession = Depends(get_db_session),
    clock: Clock = Depends(get_clock),
) -> DailyPromptResponse:
    return await PromptService(session, clock).get_by_id(prompt_id)
