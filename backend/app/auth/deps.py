"""Authenticated-user FastAPI dependencies."""

from __future__ import annotations

from fastapi import Depends, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.jwt import TokenVerifier, get_token_verifier
from app.core.errors import AppError
from app.core.settings import Settings, get_settings
from app.db.session import get_db_session
from app.models.user import User
from app.services.users import UserService

_bearer = HTTPBearer(auto_error=False)


async def get_current_user(
    request: Request,
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer),
    session: AsyncSession = Depends(get_db_session),
    settings: Settings = Depends(get_settings),
) -> User:
    if credentials is None or credentials.scheme.lower() != "bearer" or not credentials.credentials:
        raise AppError(
            code="unauthenticated",
            message="Authentication is required.",
            status_code=401,
            details={"reason": "missing_token"},
        )

    verifier: TokenVerifier = getattr(
        request.app.state, "token_verifier", None
    ) or get_token_verifier(settings)
    verified = verifier.verify(credentials.credentials)
    return await UserService(session).resolve_or_provision(verified)


async def get_current_user_allowing_pending_deletion(
    request: Request,
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer),
    session: AsyncSession = Depends(get_db_session),
    settings: Settings = Depends(get_settings),
) -> User:
    """Like get_current_user, but permits pending_deletion for idempotent DELETE /me."""
    if credentials is None or credentials.scheme.lower() != "bearer" or not credentials.credentials:
        raise AppError(
            code="unauthenticated",
            message="Authentication is required.",
            status_code=401,
            details={"reason": "missing_token"},
        )

    verifier: TokenVerifier = getattr(
        request.app.state, "token_verifier", None
    ) or get_token_verifier(settings)
    verified = verifier.verify(credentials.credentials)
    return await UserService(session).resolve_or_provision(
        verified,
        allow_pending_deletion=True,
    )


async def get_optional_current_user(
    request: Request,
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer),
    session: AsyncSession = Depends(get_db_session),
    settings: Settings = Depends(get_settings),
) -> User | None:
    """Return the authenticated user when a bearer token is present, else None.

    Invalid, expired, or unverifiable tokens fall back to anonymous so public
    reads (feed, profiles) stay available during auth outages.
    """
    if credentials is None or credentials.scheme.lower() != "bearer" or not credentials.credentials:
        return None
    verifier: TokenVerifier = getattr(
        request.app.state, "token_verifier", None
    ) or get_token_verifier(settings)
    try:
        verified = verifier.verify(credentials.credentials)
        return await UserService(session).resolve_or_provision(verified)
    except AppError:
        return None
