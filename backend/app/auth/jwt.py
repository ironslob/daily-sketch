"""JWT verification for Descope-issued session tokens."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Protocol

import jwt
from jwt import PyJWKClient

from app.core.errors import AppError
from app.core.settings import Settings


@dataclass(frozen=True, slots=True)
class VerifiedToken:
    """Claims extracted from a verified Descope JWT."""

    subject: str
    claims: dict[str, Any]

    @property
    def display_name(self) -> str | None:
        name = self.claims.get("name")
        if isinstance(name, str) and name.strip():
            return name.strip()
        return None


class TokenVerifier(Protocol):
    """Protocol for JWT verification (real JWKS or test double)."""

    def verify(self, token: str) -> VerifiedToken: ...


class DescopeTokenVerifier:
    """Verify Descope JWTs using JWKS (PyJWKClient caches keys)."""

    def __init__(self, settings: Settings) -> None:
        self._settings = settings
        self._jwks_client = PyJWKClient(settings.resolved_descope_jwks_url, cache_keys=True)

    def verify(self, token: str) -> VerifiedToken:
        try:
            signing_key = self._jwks_client.get_signing_key_from_jwt(token)
            claims = jwt.decode(
                token,
                signing_key.key,
                algorithms=["RS256"],
                audience=self._settings.descope_audience,
                issuer=self._settings.descope_issuer,
                options={
                    "require": ["exp", "iss", "sub"],
                    "verify_aud": True,
                },
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


_verifier: TokenVerifier | None = None


def get_token_verifier(settings: Settings) -> TokenVerifier:
    global _verifier
    if _verifier is None:
        if settings.descope_project_id == "replace-me" or settings.descope_project_id.startswith(
            "replace-me"
        ):
            from app.auth.local_dev import LocalDevTokenVerifier

            _verifier = LocalDevTokenVerifier()
        else:
            _verifier = DescopeTokenVerifier(settings)
    return _verifier


def set_token_verifier(verifier: TokenVerifier | None) -> None:
    """Override the process-wide verifier (tests)."""
    global _verifier
    _verifier = verifier
