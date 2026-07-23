"""Descope SDK token verifier unit tests (mocked client)."""

from __future__ import annotations

from unittest.mock import MagicMock

import pytest
from descope import AuthException

from app.auth.jwt import DescopeTokenVerifier
from app.core.errors import AppError
from app.core.settings import Settings


@pytest.fixture
def settings(monkeypatch: pytest.MonkeyPatch) -> Settings:
    monkeypatch.setenv("DESCOPE_PROJECT_ID", "P123")
    return Settings(_env_file=None)  # type: ignore[call-arg]


def test_descope_verifier_accepts_valid_session(settings: Settings) -> None:
    client = MagicMock()
    client.validate_session.return_value = {
        "userId": "user-1",
        "sub": "user-1",
        "name": "Ada",
    }
    verifier = DescopeTokenVerifier(settings, client=client)

    verified = verifier.verify("session-jwt")

    assert verified.subject == "user-1"
    assert verified.display_name == "Ada"
    client.validate_session.assert_called_once_with(
        session_token="session-jwt",
        audience=None,
    )


def test_descope_verifier_uses_audience_override(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("DESCOPE_PROJECT_ID", "P123")
    monkeypatch.setenv("DESCOPE_AUDIENCE", "custom-aud")
    settings = Settings(_env_file=None)  # type: ignore[call-arg]
    client = MagicMock()
    client.validate_session.return_value = {"userId": "user-1", "sub": "user-1"}
    verifier = DescopeTokenVerifier(settings, client=client)

    verifier.verify("session-jwt")

    client.validate_session.assert_called_once_with(
        session_token="session-jwt",
        audience="custom-aud",
    )


def test_descope_verifier_maps_expired_token(settings: Settings) -> None:
    client = MagicMock()
    client.validate_session.side_effect = AuthException(
        401,
        "invalid_token",
        "Received expired token (exp in past) during jwt validation.",
    )
    verifier = DescopeTokenVerifier(settings, client=client)

    with pytest.raises(AppError) as exc_info:
        verifier.verify("expired-jwt")

    assert exc_info.value.status_code == 401
    assert exc_info.value.details.get("reason") == "token_expired"


def test_descope_verifier_maps_invalid_token(settings: Settings) -> None:
    client = MagicMock()
    client.validate_session.side_effect = AuthException(400, "invalid_token", "bad token")
    verifier = DescopeTokenVerifier(settings, client=client)

    with pytest.raises(AppError) as exc_info:
        verifier.verify("bad-jwt")

    assert exc_info.value.status_code == 401
    assert exc_info.value.details.get("reason") == "invalid_token"


def test_descope_verifier_requires_subject(settings: Settings) -> None:
    client = MagicMock()
    client.validate_session.return_value = {"name": "Ada"}
    verifier = DescopeTokenVerifier(settings, client=client)

    with pytest.raises(AppError) as exc_info:
        verifier.verify("session-jwt")

    assert exc_info.value.details.get("reason") == "missing_subject"
