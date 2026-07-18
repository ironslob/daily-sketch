"""User persistence helpers."""

from __future__ import annotations

import uuid

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.user import User, UserStatus


class UserRepository:
    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def get_by_descope_subject(self, descope_subject: str) -> User | None:
        result = await self._session.execute(
            select(User).where(User.descope_subject == descope_subject)
        )
        return result.scalar_one_or_none()

    async def get_by_id(self, user_id: uuid.UUID) -> User | None:
        result = await self._session.execute(select(User).where(User.id == user_id))
        return result.scalar_one_or_none()

    async def create(
        self,
        *,
        descope_subject: str,
        display_name: str,
        status: UserStatus = UserStatus.incomplete,
    ) -> User:
        user = User(
            id=uuid.uuid4(),
            descope_subject=descope_subject,
            display_name=display_name,
            status=status,
        )
        self._session.add(user)
        try:
            await self._session.commit()
        except IntegrityError:
            await self._session.rollback()
            existing = await self.get_by_descope_subject(descope_subject)
            if existing is not None:
                return existing
            raise
        await self._session.refresh(user)
        return user
