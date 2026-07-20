"""Phase 11 internal moderation operator endpoints."""

from __future__ import annotations

import os
import uuid
from collections.abc import AsyncGenerator
from datetime import UTC, datetime
from typing import Any

import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.auth.jwt import set_token_verifier
from app.core.clock import Clock, get_clock
from app.core.settings import Settings, get_settings
from app.db.session import Base, get_db_session
from app.main import create_app
from app.models.daily_prompt import DailyPrompt  # noqa: F401
from app.models.idempotency_key import IdempotencyKey  # noqa: F401
from app.models.moderation_action import ModerationAction
from app.models.report import Report, ReportStatus  # noqa: F401
from app.models.sketch_session import SketchSession  # noqa: F401
from app.models.sketch_session_event import SketchSessionEvent  # noqa: F401
from app.models.submission import Submission, SubmissionStatus  # noqa: F401
from app.models.upload import Upload  # noqa: F401
from app.models.user import User, UserStatus  # noqa: F401
from app.models.user_block import UserBlock  # noqa: F401
from app.models.user_preferences import UserPreferences  # noqa: F401
from app.repositories.prompts import PromptRepository
from app.storage.base import get_storage_adapter
from fake_storage import InMemoryStorageAdapter
from jwt_helpers import StaticTokenVerifier, generate_rsa_keypair, mint_token
from test_uploads_submissions import (
    FixedClock,
    _complete_profile,
    _create_ready_session,
    _create_ready_upload,
)

DATABASE_URL = os.environ.get(
    "DATABASE_URL",
    "postgresql+asyncpg://dailysketch:dailysketch@localhost:5432/dailysketch",  # pragma: allowlist secret
)

OPERATOR_TOKEN = "test-operator-token"

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
    clock = FixedClock(datetime(2026, 7, 19, 12, 0, tzinfo=UTC))
    session_factory = async_sessionmaker(db_engine, expire_on_commit=False, class_=AsyncSession)
    fake_storage = InMemoryStorageAdapter()
    settings = get_settings().model_copy(update={"moderation_operator_token": OPERATOR_TOKEN})

    app = create_app()
    app.state.token_verifier = verifier
    app.state.test_private_key = private_key

    async def override_db() -> AsyncGenerator[AsyncSession]:
        async with session_factory() as session:
            yield session

    def override_clock() -> Clock:
        return clock

    def override_storage() -> InMemoryStorageAdapter:
        return fake_storage

    def override_settings() -> Settings:
        return settings

    app.dependency_overrides[get_db_session] = override_db
    app.dependency_overrides[get_clock] = override_clock
    app.dependency_overrides[get_storage_adapter] = override_storage
    app.dependency_overrides[get_settings] = override_settings

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as http_client:
        http_client.app = app  # type: ignore[attr-defined]
        http_client.clock = clock  # type: ignore[attr-defined]
        http_client.session_factory = session_factory  # type: ignore[attr-defined]
        http_client.storage = fake_storage  # type: ignore[attr-defined]
        yield http_client

    app.dependency_overrides.clear()
    set_token_verifier(None)


def _auth_headers(client: AsyncClient, *, subject: str | None = None) -> dict[str, str]:
    private_key = client.app.state.test_private_key  # type: ignore[attr-defined]
    token = mint_token(private_key, subject=subject or f"descope|{uuid.uuid4()}")
    return {"Authorization": f"Bearer {token}"}


def _operator_headers() -> dict[str, str]:
    return {"X-Moderation-Token": OPERATOR_TOKEN}


async def _publish(client: AsyncClient, headers: dict[str, str]) -> dict[str, Any]:
    today = client.clock.today()  # type: ignore[attr-defined]
    session_factory = client.session_factory  # type: ignore[attr-defined]
    async with session_factory() as session:
        prompt = await PromptRepository(session).upsert_published(
            prompt_date=today,
            word_1="A",
            word_2="B",
            word_3="C",
            published_at=datetime.combine(today, datetime.min.time(), tzinfo=UTC),
        )
    session_id = await _create_ready_session(client, headers, prompt.id)
    upload = await _create_ready_upload(client, headers)
    created = await client.post(
        "/api/v1/submissions",
        headers={**headers, "Idempotency-Key": str(uuid.uuid4())},
        json={
            "sketch_session_id": session_id,
            "upload_id": upload["id"],
            "caption": "moderate me",
        },
    )
    assert created.status_code == 201, created.text
    return created.json()


@requires_postgres
@pytest.mark.asyncio
async def test_moderation_forbidden_without_token(client: AsyncClient) -> None:
    response = await client.get("/internal/moderation/reports")
    assert response.status_code == 403
    assert response.json()["error"]["code"] == "moderation_forbidden"


@requires_postgres
@pytest.mark.asyncio
async def test_moderation_inspect_hide_suspend_restore_and_audit(client: AsyncClient) -> None:
    author_headers = _auth_headers(client, subject="descope|author")
    reporter_headers = _auth_headers(client, subject="descope|reporter")
    author = await _complete_profile(client, author_headers, username="mod_author")
    await _complete_profile(client, reporter_headers, username="mod_reporter")
    submission = await _publish(client, author_headers)

    report = await client.post(
        "/api/v1/reports",
        headers=reporter_headers,
        json={
            "target_type": "submission",
            "target_id": submission["id"],
            "reason": "inappropriate",
        },
    )
    assert report.status_code == 201

    listed = await client.get("/internal/moderation/reports", headers=_operator_headers())
    assert listed.status_code == 200
    assert len(listed.json()["items"]) >= 1

    inspect = await client.get(
        f"/internal/moderation/targets/submission/{submission['id']}",
        headers=_operator_headers(),
    )
    assert inspect.status_code == 200
    assert "id" in inspect.json()

    hide = await client.post(
        f"/internal/moderation/submissions/{submission['id']}/hide",
        headers=_operator_headers(),
        json={"reason": "off-topic spam", "report_id": report.json()["id"]},
    )
    assert hide.status_code == 200

    public = await client.get(f"/api/v1/submissions/{submission['id']}")
    assert public.status_code == 404

    restore = await client.post(
        f"/internal/moderation/submissions/{submission['id']}/restore",
        headers=_operator_headers(),
        json={"reason": "false positive"},
    )
    assert restore.status_code == 200

    restored = await client.get(f"/api/v1/submissions/{submission['id']}")
    assert restored.status_code == 200

    suspend = await client.post(
        f"/internal/moderation/users/{author['id']}/suspend",
        headers=_operator_headers(),
        json={"reason": "repeat abuse"},
    )
    assert suspend.status_code == 200

    session_factory = client.session_factory  # type: ignore[attr-defined]
    async with session_factory() as session:
        actions = (await session.execute(select(ModerationAction))).scalars().all()
        assert len(actions) >= 2
        user = (
            await session.execute(select(User).where(User.id == uuid.UUID(author["id"])))
        ).scalar_one()
        assert user.status == UserStatus.suspended
