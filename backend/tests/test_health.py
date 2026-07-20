"""Health endpoint smoke tests."""

from collections.abc import AsyncGenerator
from unittest.mock import AsyncMock, patch

import pytest
from app.main import create_app
from httpx import ASGITransport, AsyncClient


@pytest.fixture
async def client() -> AsyncGenerator[AsyncClient]:
    app = create_app()
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as http_client:
        yield http_client


@pytest.mark.asyncio
async def test_live_returns_ok(client: AsyncClient) -> None:
    response = await client.get("/health/live")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


@pytest.mark.asyncio
async def test_ready_returns_ok_when_database_available(client: AsyncClient) -> None:
    mock_session = AsyncMock()
    mock_session.execute = AsyncMock(return_value=None)
    mock_session.__aenter__ = AsyncMock(return_value=mock_session)
    mock_session.__aexit__ = AsyncMock(return_value=None)

    mock_storage = AsyncMock()
    mock_storage.ping = AsyncMock(return_value=True)

    with (
        patch("app.api.health.SessionLocal", return_value=mock_session),
        patch("app.api.health.get_storage_adapter", return_value=mock_storage),
    ):
        response = await client.get("/health/ready")

    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "ok"
    assert body["checks"]["database"] == "ok"
    assert body["checks"]["storage_config"] == "ok"
    assert body["checks"]["storage"] == "ok"


@pytest.mark.asyncio
async def test_version_includes_release_metadata(client: AsyncClient) -> None:
    response = await client.get("/health/version")
    assert response.status_code == 200
    body = response.json()
    assert body["release_version"] == "0.1.0"
    assert "environment" in body


@pytest.mark.asyncio
async def test_ready_returns_503_when_database_unavailable(client: AsyncClient) -> None:
    mock_session = AsyncMock()
    mock_session.execute = AsyncMock(side_effect=RuntimeError("db down"))
    mock_session.__aenter__ = AsyncMock(return_value=mock_session)
    mock_session.__aexit__ = AsyncMock(return_value=None)

    mock_storage = AsyncMock()
    mock_storage.ping = AsyncMock(return_value=True)

    with (
        patch("app.api.health.SessionLocal", return_value=mock_session),
        patch("app.api.health.get_storage_adapter", return_value=mock_storage),
    ):
        response = await client.get("/health/ready")

    assert response.status_code == 503
    body = response.json()
    assert body["status"] == "unavailable"
    assert body["checks"]["database"] == "unavailable"
