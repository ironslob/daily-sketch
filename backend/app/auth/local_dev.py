"""Local development JWT verifier for placeholder Descope configuration."""

from __future__ import annotations

import jwt

from app.auth.jwt import VerifiedToken
from app.core.errors import AppError

# Public placeholder secret for local/mock auth only. Never use in production.
LOCAL_DEV_JWT_SECRET = "daily-sketch-local-dev-only-secret!!"  # pragma: allowlist secret
LOCAL_DEV_ALGORITHM = "HS256"
LOCAL_DEV_ISSUER = "daily-sketch-local"
LOCAL_DEV_AUDIENCE = "daily-sketch-local"


class LocalDevTokenVerifier:
    """Accept HS256 JWTs minted by the iOS MockAuthService when Descope is unconfigured."""

    def verify(self, token: str) -> VerifiedToken:
        try:
            claims = jwt.decode(
                token,
                LOCAL_DEV_JWT_SECRET,
                algorithms=[LOCAL_DEV_ALGORITHM],
                audience=LOCAL_DEV_AUDIENCE,
                issuer=LOCAL_DEV_ISSUER,
                options={"require": ["exp", "iss", "sub"]},
            )
        except jwt.ExpiredSignatureError as exc:
            raise AppError(
                code="unauthenticated",
                message="Authentication is required.",
                status_code=401,
                details={"reason": "token_expired"},
            ) from exc
        except jwt.InvalidTokenError as exc:
            raise AppError(
                code="unauthenticated",
                message="Authentication is required.",
                status_code=401,
                details={"reason": "invalid_token"},
            ) from exc

        subject = claims.get("sub")
        if not isinstance(subject, str) or not subject:
            raise AppError(
                code="unauthenticated",
                message="Authentication is required.",
                status_code=401,
                details={"reason": "missing_subject"},
            )
        return VerifiedToken(subject=subject, claims=claims)
