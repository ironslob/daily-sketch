"""Health endpoint contract tests against OpenAPI schemas."""

from __future__ import annotations

from collections.abc import AsyncGenerator
from pathlib import Path
from typing import Any
from unittest.mock import AsyncMock, patch

import pytest
import yaml
from app.main import create_app
from httpx import ASGITransport, AsyncClient
from jsonschema import Draft202012Validator

REPO_ROOT = Path(__file__).resolve().parents[2]
OPENAPI_PATH = REPO_ROOT / "api" / "openapi" / "openapi.yaml"


@pytest.fixture(scope="module")
def openapi_spec() -> dict[str, Any]:
    with OPENAPI_PATH.open(encoding="utf-8") as handle:
        loaded = yaml.safe_load(handle)
    assert isinstance(loaded, dict)
    return loaded


def assert_matches_schema(
    instance: object,
    schema_name: str,
    openapi_spec: dict[str, Any],
) -> None:
    schema = openapi_spec["components"]["schemas"][schema_name]
    Draft202012Validator(schema).validate(instance)


@pytest.fixture
async def client() -> AsyncGenerator[AsyncClient]:
    app = create_app()
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as http_client:
        yield http_client


@pytest.mark.asyncio
async def test_live_response_matches_contract(
    client: AsyncClient,
    openapi_spec: dict[str, Any],
) -> None:
    response = await client.get("/health/live")
    assert response.status_code == 200
    assert_matches_schema(response.json(), "HealthLiveResponse", openapi_spec)


@pytest.mark.asyncio
async def test_ready_ok_response_matches_contract(
    client: AsyncClient,
    openapi_spec: dict[str, Any],
) -> None:
    mock_session = AsyncMock()
    mock_session.execute = AsyncMock(return_value=None)
    mock_session.__aenter__ = AsyncMock(return_value=mock_session)
    mock_session.__aexit__ = AsyncMock(return_value=None)

    with (
        patch("app.api.health.SessionLocal", return_value=mock_session),
        patch("app.api.health.get_storage_adapter") as mock_storage_factory,
    ):
        mock_storage = AsyncMock()
        mock_storage.ping = AsyncMock(return_value=True)
        mock_storage_factory.return_value = mock_storage
        response = await client.get("/health/ready")

    assert response.status_code == 200
    assert_matches_schema(response.json(), "HealthReadyResponse", openapi_spec)


@pytest.mark.asyncio
async def test_ready_unavailable_response_matches_contract(
    client: AsyncClient,
    openapi_spec: dict[str, Any],
) -> None:
    mock_session = AsyncMock()
    mock_session.execute = AsyncMock(side_effect=RuntimeError("db down"))
    mock_session.__aenter__ = AsyncMock(return_value=mock_session)
    mock_session.__aexit__ = AsyncMock(return_value=None)

    with (
        patch("app.api.health.SessionLocal", return_value=mock_session),
        patch("app.api.health.get_storage_adapter") as mock_storage_factory,
    ):
        mock_storage = AsyncMock()
        mock_storage.ping = AsyncMock(return_value=True)
        mock_storage_factory.return_value = mock_storage
        response = await client.get("/health/ready")

    assert response.status_code == 503
    assert_matches_schema(response.json(), "HealthReadyResponse", openapi_spec)
