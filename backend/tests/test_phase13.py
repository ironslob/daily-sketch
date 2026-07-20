"""Phase 13 production hardening tests."""

import pytest
from app.core.redaction import redact_string, redact_value
from app.core.settings import Settings
from app.main import create_app
from httpx import ASGITransport, AsyncClient
from pydantic import ValidationError


def test_redact_string_removes_bearer_and_signed_urls() -> None:
    value = "Bearer secret-token https://cdn.test/file?X-Amz-Signature=abc123"
    redacted = redact_string(value)
    assert "secret-token" not in redacted
    assert "X-Amz-Signature=abc123" not in redacted
    assert "[REDACTED]" in redacted


def test_redact_value_masks_sensitive_keys() -> None:
    payload = {"authorization": "Bearer x", "caption": "hello", "nested": {"token": "abc"}}
    redacted = redact_value(payload)
    assert redacted["authorization"] == "[REDACTED]"
    assert redacted["caption"] == "[REDACTED]"
    assert redacted["nested"]["token"] == "[REDACTED]"


def test_staging_settings_fail_without_descope(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("APP_ENV", "staging")
    monkeypatch.setenv("DESCOPE_PROJECT_ID", "replace-me")
    monkeypatch.setenv("MODERATION_OPERATOR_TOKEN", "staging-token")
    with pytest.raises(ValidationError):
        Settings(_env_file=None)  # type: ignore[call-arg]


def test_staging_settings_fail_on_replace_me_prefix(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("APP_ENV", "staging")
    monkeypatch.setenv("DESCOPE_PROJECT_ID", "replace-me-staging")
    monkeypatch.setenv("DESCOPE_AUDIENCE", "replace-me-staging")
    monkeypatch.setenv("DESCOPE_ISSUER", "https://api.descope.com/v1/apps/replace-me-staging")
    monkeypatch.setenv("MODERATION_OPERATOR_TOKEN", "staging-token")
    with pytest.raises(ValidationError):
        Settings(_env_file=None)  # type: ignore[call-arg]


def test_staging_settings_accept_valid_config(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("APP_ENV", "staging")
    monkeypatch.setenv("DESCOPE_PROJECT_ID", "P123")
    monkeypatch.setenv("DESCOPE_AUDIENCE", "daily-sketch")
    monkeypatch.setenv("DESCOPE_ISSUER", "https://api.descope.com/v1/apps/P123")
    monkeypatch.setenv("MODERATION_OPERATOR_TOKEN", "staging-token")
    monkeypatch.setenv("STORAGE_ACCESS_KEY", "remote-key")
    monkeypatch.setenv("STORAGE_SECRET_KEY", "remote-secret")
    monkeypatch.setenv("STORAGE_USE_SSL", "true")
    monkeypatch.setenv("STORAGE_ENDPOINT", "https://storage.example.com")
    monkeypatch.setenv("DB_SSL_REQUIRE", "true")
    monkeypatch.setenv(
        "DATABASE_URL",
        "postgresql+asyncpg://user:pass@db.example.com:5432/dailysketch",  # pragma: allowlist secret
    )
    settings = Settings(_env_file=None)  # type: ignore[call-arg]
    assert settings.app_env == "staging"


@pytest.mark.asyncio
async def test_request_body_size_limit_returns_413() -> None:
    app = create_app()
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.post(
            "/api/v1/reports",
            headers={"Content-Length": "2000000"},
            content=b"{}",
        )
    assert response.status_code == 413


@pytest.mark.asyncio
async def test_rate_limit_returns_429(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("RATE_LIMIT_REPORT_MAX", "1")
    monkeypatch.setenv("RATE_LIMIT_WINDOW_SECONDS", "60")
    from app.core import settings as settings_module

    settings_module.get_settings.cache_clear()
    app = create_app()
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        first = await client.post("/api/v1/reports", headers={"Content-Length": "2"}, content=b"{}")
        second = await client.post(
            "/api/v1/reports", headers={"Content-Length": "2"}, content=b"{}"
        )
    settings_module.get_settings.cache_clear()
    assert first.status_code in {401, 413, 422, 429}
    assert second.status_code == 429
    assert second.headers.get("retry-after") is not None
