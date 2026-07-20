"""Request ID middleware behaviour."""

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
async def test_live_response_includes_generated_request_id(client: AsyncClient) -> None:
    response = await client.get("/health/live")
    assert response.status_code == 200
    request_id = response.headers.get("X-Request-ID")
    assert request_id is not None
    assert len(request_id) == 36


@pytest.mark.asyncio
async def test_inbound_request_id_is_echoed(client: AsyncClient) -> None:
    expected = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
    response = await client.get("/health/live", headers={"X-Request-ID": expected})
    assert response.status_code == 200
    assert response.headers.get("X-Request-ID") == expected


@pytest.mark.asyncio
async def test_ready_response_includes_request_id(client: AsyncClient) -> None:
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
    assert response.headers.get("X-Request-ID")
