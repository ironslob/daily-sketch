"""Reflection repository."""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import datetime

from sqlalchemy import and_, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.reflection import Reflection, ReflectionStatus
from app.models.user import User, UserStatus


@dataclass(frozen=True, slots=True)
class ReflectionRow:
    reflection: Reflection
    user: User


class ReflectionRepository:
    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def create(
        self,
        *,
        submission_id: uuid.UUID,
        user_id: uuid.UUID,
        body: str,
        commit: bool = True,
    ) -> Reflection:
        reflection = Reflection(
            id=uuid.uuid4(),
            submission_id=submission_id,
            user_id=user_id,
            body=body,
            status=ReflectionStatus.published,
        )
        self._session.add(reflection)
        if commit:
            await self._session.commit()
            await self._session.refresh(reflection)
        else:
            await self._session.flush()
        return reflection

    async def get_by_id(self, reflection_id: uuid.UUID) -> Reflection | None:
        result = await self._session.execute(
            select(Reflection).where(Reflection.id == reflection_id)
        )
        return result.scalar_one_or_none()

    async def list_for_submission(
        self,
        *,
        submission_id: uuid.UUID,
        limit: int,
        cursor_created_at: datetime | None = None,
        cursor_id: uuid.UUID | None = None,
    ) -> list[ReflectionRow]:
        """Return up to ``limit`` published reflections oldest-to-newest."""
        statement = (
            select(Reflection, User)
            .join(User, User.id == Reflection.user_id)
            .where(
                Reflection.submission_id == submission_id,
                Reflection.status == ReflectionStatus.published,
                Reflection.deleted_at.is_(None),
                User.status.in_((UserStatus.incomplete, UserStatus.active)),
                User.deleted_at.is_(None),
            )
        )
        if cursor_created_at is not None and cursor_id is not None:
            statement = statement.where(
                or_(
                    Reflection.created_at > cursor_created_at,
                    and_(
                        Reflection.created_at == cursor_created_at,
                        Reflection.id > cursor_id,
                    ),
                )
            )
        statement = statement.order_by(
            Reflection.created_at.asc(),
            Reflection.id.asc(),
        ).limit(limit)

        result = await self._session.execute(statement)
        return [
            ReflectionRow(reflection=reflection, user=user) for reflection, user in result.all()
        ]

    async def soft_delete(
        self,
        reflection: Reflection,
        *,
        deleted_at: datetime,
        commit: bool = True,
    ) -> bool:
        """Soft-delete a published Reflection. Returns True on transition."""
        if reflection.status != ReflectionStatus.published or reflection.deleted_at is not None:
            return False
        reflection.status = ReflectionStatus.deleted
        reflection.deleted_at = deleted_at
        if commit:
            await self._session.commit()
            await self._session.refresh(reflection)
        else:
            await self._session.flush()
        return True

    async def list_published_for_user(self, user_id: uuid.UUID) -> list[Reflection]:
        result = await self._session.execute(
            select(Reflection).where(
                Reflection.user_id == user_id,
                Reflection.status == ReflectionStatus.published,
                Reflection.deleted_at.is_(None),
            )
        )
        return list(result.scalars().all())

    async def set_moderation_status(
        self,
        reflection: Reflection,
        *,
        status: ReflectionStatus,
        deleted_at: datetime | None = None,
        commit: bool = True,
    ) -> Reflection:
        reflection.status = status
        if deleted_at is not None:
            reflection.deleted_at = deleted_at
        elif status == ReflectionStatus.published:
            reflection.deleted_at = None
        if commit:
            await self._session.commit()
            await self._session.refresh(reflection)
        else:
            await self._session.flush()
        return reflection
