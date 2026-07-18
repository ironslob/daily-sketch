"""Local development JWT verifier tests."""

from __future__ import annotations

import time

import jwt
import pytest

from app.auth.local_dev import (
    LOCAL_DEV_AUDIENCE,
    LOCAL_DEV_ISSUER,
    LOCAL_DEV_JWT_SECRET,
    LocalDevTokenVerifier,
)
from app.core.errors import AppError


def _mint(*, expires_in: int = 3600, subject: str = "local|abc") -> str:
    now = int(time.time())
    return jwt.encode(
        {
            "sub": subject,
            "name": "Local",
            "iss": LOCAL_DEV_ISSUER,
            "aud": LOCAL_DEV_AUDIENCE,
            "iat": now,
            "exp": now + expires_in,
        },
        LOCAL_DEV_JWT_SECRET,
        algorithm="HS256",
    )


def test_local_dev_token_accepted() -> None:
    verified = LocalDevTokenVerifier().verify(_mint())
    assert verified.subject == "local|abc"
    assert verified.display_name == "Local"


def test_local_dev_expired_rejected() -> None:
    with pytest.raises(AppError) as exc_info:
        LocalDevTokenVerifier().verify(_mint(expires_in=-10))
    assert exc_info.value.status_code == 401
