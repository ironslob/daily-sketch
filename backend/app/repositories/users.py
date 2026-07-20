"""User persistence helpers."""

from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import AppError
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

    async def get_by_username_normalized(self, username_normalized: str) -> User | None:
        result = await self._session.execute(
            select(User).where(User.username_normalized == username_normalized)
        )
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

    async def update_profile(
        self,
        user: User,
        *,
        username: str | None = None,
        username_normalized: str | None = None,
        display_name: str | None = None,
        bio: str | None | object = ...,
        avatar_upload_id: uuid.UUID | None | object = ...,
        status: UserStatus | None = None,
        profile_completed_at: datetime | None | object = ...,
        deleted_at: datetime | None | object = ...,
        commit: bool = True,
    ) -> User:
        if username is not None:
            user.username = username
        if username_normalized is not None:
            user.username_normalized = username_normalized
        if display_name is not None:
            user.display_name = display_name
        if bio is not ...:
            user.bio = bio  # type: ignore[assignment]
        if avatar_upload_id is not ...:
            user.avatar_upload_id = avatar_upload_id  # type: ignore[assignment]
        if status is not None:
            user.status = status
        if profile_completed_at is not ...:
            user.profile_completed_at = profile_completed_at  # type: ignore[assignment]
        if deleted_at is not ...:
            user.deleted_at = deleted_at  # type: ignore[assignment]

        if not commit:
            await self._session.flush()
            return user

        try:
            await self._session.commit()
        except IntegrityError as exc:
            await self._session.rollback()
            raise AppError(
                code="username_taken",
                message="That username is already taken.",
                status_code=409,
            ) from exc
        await self._session.refresh(user)
        return user

    async def list_pending_deletion(self) -> list[User]:
        result = await self._session.execute(
            select(User).where(User.status == UserStatus.pending_deletion)
        )
        return list(result.scalars().all())

    async def set_status(
        self,
        user: User,
        *,
        status: UserStatus,
        deleted_at: datetime | None | object = ...,
        commit: bool = True,
    ) -> User:
        return await self.update_profile(
            user,
            status=status,
            deleted_at=deleted_at,
            commit=commit,
        )
