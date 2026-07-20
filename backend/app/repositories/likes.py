"""Submission Like repository."""

from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.submission_like import SubmissionLike


class LikeRepository:
    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def exists(self, *, submission_id: uuid.UUID, user_id: uuid.UUID) -> bool:
        result = await self._session.execute(
            select(SubmissionLike.submission_id).where(
                SubmissionLike.submission_id == submission_id,
                SubmissionLike.user_id == user_id,
            )
        )
        return result.scalar_one_or_none() is not None

    async def liked_submission_ids(
        self,
        *,
        user_id: uuid.UUID,
        submission_ids: list[uuid.UUID],
    ) -> set[uuid.UUID]:
        if not submission_ids:
            return set()
        result = await self._session.execute(
            select(SubmissionLike.submission_id).where(
                SubmissionLike.user_id == user_id,
                SubmissionLike.submission_id.in_(submission_ids),
            )
        )
        return set(result.scalars().all())

    async def add(
        self,
        *,
        submission_id: uuid.UUID,
        user_id: uuid.UUID,
        created_at: datetime,
        commit: bool = True,
    ) -> bool:
        """Insert a Like. Returns True when a new row was inserted."""
        statement = (
            insert(SubmissionLike)
            .values(
                submission_id=submission_id,
                user_id=user_id,
                created_at=created_at,
            )
            .on_conflict_do_nothing(
                index_elements=[SubmissionLike.submission_id, SubmissionLike.user_id]
            )
            .returning(SubmissionLike.submission_id)
        )
        result = await self._session.execute(statement)
        inserted = result.scalar_one_or_none() is not None
        if commit:
            await self._session.commit()
        else:
            await self._session.flush()
        return inserted

    async def delete(
        self,
        *,
        submission_id: uuid.UUID,
        user_id: uuid.UUID,
        commit: bool = True,
    ) -> bool:
        """Delete a Like. Returns True when a row was deleted."""
        existing = await self._session.get(
            SubmissionLike,
            (submission_id, user_id),
        )
        if existing is None:
            return False
        await self._session.delete(existing)
        if commit:
            await self._session.commit()
        else:
            await self._session.flush()
        return True

    async def list_for_user(self, user_id: uuid.UUID) -> list[SubmissionLike]:
        result = await self._session.execute(
            select(SubmissionLike).where(SubmissionLike.user_id == user_id)
        )
        return list(result.scalars().all())
