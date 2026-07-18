"""User application services."""

from __future__ import annotations

from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.jwt import VerifiedToken
from app.core.errors import AppError
from app.models.user import User, UserStatus
from app.repositories.users import UserRepository

DEFAULT_DISPLAY_NAME = "New sketcher"


class UserService:
    def __init__(self, session: AsyncSession) -> None:
        self._repo = UserRepository(session)

    async def resolve_or_provision(self, token: VerifiedToken) -> User:
        existing = await self._repo.get_by_descope_subject(token.subject)
        if existing is not None:
            self._enforce_account_status(existing)
            return existing

        display_name = token.display_name or DEFAULT_DISPLAY_NAME
        user = await self._repo.create(
            descope_subject=token.subject,
            display_name=display_name,
            status=UserStatus.incomplete,
        )
        self._enforce_account_status(user)
        return user

    @staticmethod
    def _enforce_account_status(user: User) -> None:
        if user.status == UserStatus.suspended:
            raise AppError(
                code="account_suspended",
                message="This account has been suspended.",
                status_code=403,
            )
        if user.status in {UserStatus.pending_deletion, UserStatus.deleted}:
            raise AppError(
                code="account_unavailable",
                message="This account is no longer available.",
                status_code=403,
            )
