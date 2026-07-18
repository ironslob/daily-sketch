"""Shared JWT test helpers — local RSA keys, no network calls to Descope."""

from __future__ import annotations

import time
import uuid
from typing import Any

import jwt
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa

from app.auth.jwt import VerifiedToken
from app.core.errors import AppError

ISSUER = "https://api.descope.com/v1/apps/test-project"
AUDIENCE = "test-project"


def generate_rsa_keypair() -> tuple[Any, Any]:
    private_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    return private_key, private_key.public_key()


def private_pem(private_key: Any) -> bytes:
    return private_key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    )


def mint_token(
    private_key: Any,
    *,
    subject: str | None = None,
    issuer: str = ISSUER,
    audience: str = AUDIENCE,
    expires_in: int = 3600,
    name: str | None = None,
    extra_claims: dict[str, Any] | None = None,
) -> str:
    now = int(time.time())
    claims: dict[str, Any] = {
        "sub": subject or f"descope|{uuid.uuid4()}",
        "iss": issuer,
        "aud": audience,
        "iat": now,
        "exp": now + expires_in,
    }
    if name is not None:
        claims["name"] = name
    if extra_claims:
        claims.update(extra_claims)
    return jwt.encode(claims, private_pem(private_key), algorithm="RS256")


class StaticTokenVerifier:
    """Test double that verifies tokens with a fixed RSA private key."""

    def __init__(
        self,
        private_key: Any,
        *,
        issuer: str = ISSUER,
        audience: str = AUDIENCE,
    ) -> None:
        self._private_key = private_key
        self._issuer = issuer
        self._audience = audience

    def verify(self, token: str) -> VerifiedToken:
        try:
            claims = jwt.decode(
                token,
                self._private_key.public_key(),
                algorithms=["RS256"],
                audience=self._audience,
                issuer=self._issuer,
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
