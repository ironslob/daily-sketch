"""User application services."""

from __future__ import annotations

import uuid

from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.jwt import VerifiedToken
from app.core.errors import AppError
from app.models.user import User, UserStatus
from app.repositories.preferences import PreferencesRepository
from app.repositories.users import UserRepository

DEFAULT_DISPLAY_NAME = "New sketcher"


class UserService:
    def __init__(self, session: AsyncSession) -> None:
        self._repo = UserRepository(session)
        self._preferences = PreferencesRepository(session)

    async def resolve_or_provision(
        self,
        token: VerifiedToken,
        *,
        allow_pending_deletion: bool = False,
    ) -> User:
        existing = await self._repo.get_by_descope_subject(token.subject)
        if existing is not None:
            self._enforce_account_status(
                existing,
                allow_pending_deletion=allow_pending_deletion,
            )
            await self._ensure_preferences(existing.id)
            return existing

        display_name = token.display_name or DEFAULT_DISPLAY_NAME
        user = await self._repo.create(
            descope_subject=token.subject,
            display_name=display_name,
            status=UserStatus.incomplete,
        )
        await self._ensure_preferences(user.id)
        self._enforce_account_status(
            user,
            allow_pending_deletion=allow_pending_deletion,
        )
        return user

    async def _ensure_preferences(self, user_id: uuid.UUID) -> None:
        prefs = await self._preferences.get_by_user_id(user_id)
        if prefs is None:
            await self._preferences.create_defaults(user_id)

    @staticmethod
    def _enforce_account_status(
        user: User,
        *,
        allow_pending_deletion: bool = False,
    ) -> None:
        if user.status == UserStatus.suspended:
            raise AppError(
                code="account_suspended",
                message="This account has been suspended.",
                status_code=403,
            )
        if user.status == UserStatus.deleted:
            raise AppError(
                code="account_unavailable",
                message="This account is no longer available.",
                status_code=403,
            )
        if user.status == UserStatus.pending_deletion and not allow_pending_deletion:
            raise AppError(
                code="account_unavailable",
                message="This account is no longer available.",
                status_code=403,
            )
