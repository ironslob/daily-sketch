"""Daily Prompt API schemas."""

from __future__ import annotations

from datetime import date, datetime
from enum import Enum
from uuid import UUID

from pydantic import BaseModel, ConfigDict

from app.models.daily_prompt import DailyPrompt


class PromptStatusSchema(str, Enum):
    """API projection of PromptStatus."""

    draft = "draft"
    published = "published"
    withdrawn = "withdrawn"


class DailyPromptResponse(BaseModel):
    """Published Daily Prompt response."""

    model_config = ConfigDict(extra="forbid")

    id: UUID
    prompt_date: date
    word_1: str
    word_2: str
    word_3: str
    status: PromptStatusSchema
    published_at: datetime | None

    @classmethod
    def from_orm(cls, prompt: DailyPrompt) -> DailyPromptResponse:
        return cls(
            id=prompt.id,
            prompt_date=prompt.prompt_date,
            word_1=prompt.word_1,
            word_2=prompt.word_2,
            word_3=prompt.word_3,
            status=PromptStatusSchema(prompt.status.value),
            published_at=prompt.published_at,
        )
