"""GET /api/v1/me integration and contract tests."""

from __future__ import annotations

import os
import uuid
from collections.abc import AsyncGenerator

import pytest
from httpx import ASGITransport, AsyncClient
from jwt_helpers import StaticTokenVerifier, generate_rsa_keypair, mint_token
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.auth.jwt import set_token_verifier
from app.db.session import Base, get_db_session
from app.main import create_app
from app.models.user import User, UserStatus

DATABASE_URL = os.environ.get(
    "DATABASE_URL",
    "postgresql+asyncpg://dailysketch:dailysketch@localhost:5432/dailysketch",  # pragma: allowlist secret
)

requires_postgres = pytest.mark.skipif(
    os.environ.get("SKIP_POSTGRES_TESTS") == "1",
    reason="SKIP_POSTGRES_TESTS=1",
)


@pytest.fixture
async def db_engine():
    engine = create_async_engine(DATABASE_URL, pool_pre_ping=True)
    try:
        async with engine.begin() as conn:
            await conn.execute(text("SELECT 1"))
    except Exception as exc:  # noqa: BLE001
        await engine.dispose()
        pytest.skip(f"PostgreSQL unavailable: {exc}")
        return

    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
        await conn.run_sync(Base.metadata.create_all)

    yield engine

    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
    await engine.dispose()


@pytest.fixture
async def client(db_engine) -> AsyncGenerator[AsyncClient]:
    private_key, _ = generate_rsa_keypair()
    verifier = StaticTokenVerifier(private_key)
    set_token_verifier(verifier)

    session_factory = async_sessionmaker(db_engine, expire_on_commit=False, class_=AsyncSession)

    app = create_app()
    app.state.token_verifier = verifier
    app.state.test_private_key = private_key

    async def override_db() -> AsyncGenerator[AsyncSession]:
        async with session_factory() as session:
            yield session

    app.dependency_overrides[get_db_session] = override_db

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as http_client:
        http_client.app = app  # type: ignore[attr-defined]
        yield http_client

    app.dependency_overrides.clear()
    set_token_verifier(None)


@requires_postgres
@pytest.mark.asyncio
async def test_missing_token_rejected(client: AsyncClient) -> None:
    response = await client.get("/api/v1/me")
    assert response.status_code == 401
    body = response.json()
    assert body["error"]["code"] == "unauthenticated"
    assert "request_id" in body["error"]
    assert response.headers.get("X-Request-ID")


@requires_postgres
@pytest.mark.asyncio
async def test_invalid_signature_rejected(client: AsyncClient) -> None:
    other_key, _ = generate_rsa_keypair()
    token = mint_token(other_key)
    response = await client.get("/api/v1/me", headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 401
    assert response.json()["error"]["code"] == "unauthenticated"


@requires_postgres
@pytest.mark.asyncio
async def test_expired_token_rejected(client: AsyncClient) -> None:
    private_key = client.app.state.test_private_key  # type: ignore[attr-defined]
    token = mint_token(private_key, expires_in=-30)
    response = await client.get("/api/v1/me", headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 401
    assert response.json()["error"]["code"] == "unauthenticated"


@requires_postgres
@pytest.mark.asyncio
async def test_valid_jwt_provisions_user_once(client: AsyncClient) -> None:
    private_key = client.app.state.test_private_key  # type: ignore[attr-defined]
    subject = f"descope|{uuid.uuid4()}"
    token = mint_token(private_key, subject=subject, name="Sketchy")

    first = await client.get("/api/v1/me", headers={"Authorization": f"Bearer {token}"})
    assert first.status_code == 200
    first_body = first.json()
    assert first_body["display_name"] == "Sketchy"
    assert first_body["username"] is None
    assert first_body["profile_completed"] is False
    assert first_body["status"] == "incomplete"
    assert first_body["preferences"]["timezone"] == "UTC"
    assert first_body["preferences"]["appearance"] == "system"
    assert first_body["preferences"]["notifications_enabled"] is False
    user_id = first_body["id"]

    second = await client.get("/api/v1/me", headers={"Authorization": f"Bearer {token}"})
    assert second.status_code == 200
    assert second.json()["id"] == user_id


@requires_postgres
@pytest.mark.asyncio
async def test_repeated_login_resolves_same_user(client: AsyncClient, db_engine) -> None:
    private_key = client.app.state.test_private_key  # type: ignore[attr-defined]
    subject = f"descope|{uuid.uuid4()}"
    token_a = mint_token(private_key, subject=subject)
    token_b = mint_token(private_key, subject=subject)

    first = await client.get("/api/v1/me", headers={"Authorization": f"Bearer {token_a}"})
    second = await client.get("/api/v1/me", headers={"Authorization": f"Bearer {token_b}"})
    assert first.status_code == 200
    assert second.status_code == 200
    assert first.json()["id"] == second.json()["id"]


@requires_postgres
@pytest.mark.asyncio
async def test_suspended_account_rejected(client: AsyncClient, db_engine) -> None:
    private_key = client.app.state.test_private_key  # type: ignore[attr-defined]
    subject = f"descope|{uuid.uuid4()}"
    session_factory = async_sessionmaker(db_engine, expire_on_commit=False, class_=AsyncSession)
    async with session_factory() as session:
        user = User(
            id=uuid.uuid4(),
            descope_subject=subject,
            display_name="Suspended",
            status=UserStatus.suspended,
        )
        session.add(user)
        await session.commit()

    token = mint_token(private_key, subject=subject)
    response = await client.get("/api/v1/me", headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 403
    body = response.json()
    assert body["error"]["code"] == "account_suspended"
    assert "request_id" in body["error"]


@requires_postgres
@pytest.mark.asyncio
async def test_deleted_account_rejected(client: AsyncClient, db_engine) -> None:
    private_key = client.app.state.test_private_key  # type: ignore[attr-defined]
    subject = f"descope|{uuid.uuid4()}"
    session_factory = async_sessionmaker(db_engine, expire_on_commit=False, class_=AsyncSession)
    async with session_factory() as session:
        user = User(
            id=uuid.uuid4(),
            descope_subject=subject,
            display_name="Gone",
            status=UserStatus.deleted,
        )
        session.add(user)
        await session.commit()

    token = mint_token(private_key, subject=subject)
    response = await client.get("/api/v1/me", headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 403
    assert response.json()["error"]["code"] == "account_unavailable"
