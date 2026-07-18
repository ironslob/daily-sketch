"""Settings validation tests."""

import pytest
from app.core.settings import Settings
from pydantic import ValidationError


def test_settings_load_defaults() -> None:
    settings = Settings(
        _env_file=None,  # type: ignore[call-arg]
    )
    assert settings.app_env == "local"
    assert settings.release_version == "0.1.0"
    assert settings.prompt_date_timezone == "UTC"
    assert settings.request_timeout_seconds == 30
    assert settings.log_level == "INFO"


def test_settings_accept_env_overrides(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("APP_ENV", "development")
    monkeypatch.setenv("RELEASE_VERSION", "1.2.3")
    monkeypatch.setenv("COMMIT_SHA", "abc123")
    monkeypatch.setenv("REQUEST_TIMEOUT_SECONDS", "45")
    monkeypatch.setenv("LOG_LEVEL", "debug")

    settings = Settings(_env_file=None)  # type: ignore[call-arg]
    assert settings.app_env == "development"
    assert settings.release_version == "1.2.3"
    assert settings.commit_sha == "abc123"
    assert settings.request_timeout_seconds == 45
    assert settings.log_level == "DEBUG"


def test_settings_reject_invalid_timeout(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("REQUEST_TIMEOUT_SECONDS", "0")
    with pytest.raises(ValidationError):
        Settings(_env_file=None)  # type: ignore[call-arg]


def test_settings_reject_non_utc_prompt_timezone(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("PROMPT_DATE_TIMEZONE", "America/New_York")
    with pytest.raises(ValidationError):
        Settings(_env_file=None)  # type: ignore[call-arg]


def test_settings_reject_invalid_log_level(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("LOG_LEVEL", "verbose")
    with pytest.raises(ValidationError):
        Settings(_env_file=None)  # type: ignore[call-arg]


def test_settings_resolved_descope_jwks_url() -> None:
    settings = Settings(_env_file=None)  # type: ignore[call-arg]
    assert settings.resolved_descope_jwks_url.endswith(
        f"/{settings.descope_project_id}/.well-known/jwks.json"
    )


def test_settings_descope_jwks_url_override(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("DESCOPE_JWKS_URL", "https://example.test/jwks.json")
    settings = Settings(_env_file=None)  # type: ignore[call-arg]
    assert settings.resolved_descope_jwks_url == "https://example.test/jwks.json"
