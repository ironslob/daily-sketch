"""Phase 11 safety: blocks, reports, and account deletion."""

from __future__ import annotations

import os
import uuid
from collections.abc import AsyncGenerator
from datetime import UTC, date, datetime
from pathlib import Path
from typing import Any

import pytest
import yaml
from httpx import ASGITransport, AsyncClient
from jsonschema import Draft202012Validator
from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.auth.jwt import set_token_verifier
from app.core.clock import Clock, get_clock
from app.core.settings import Settings, get_settings
from app.db.session import Base, get_db_session
from app.main import create_app
from app.models.daily_prompt import DailyPrompt  # noqa: F401
from app.models.idempotency_key import IdempotencyKey  # noqa: F401
from app.models.moderation_action import ModerationAction  # noqa: F401
from app.models.report import Report  # noqa: F401
from app.models.sketch_session import SketchSession  # noqa: F401
from app.models.sketch_session_event import SketchSessionEvent  # noqa: F401
from app.models.submission import Submission  # noqa: F401
from app.models.upload import Upload  # noqa: F401
from app.models.user import User, UserStatus
from app.models.user_block import UserBlock  # noqa: F401
from app.models.user_preferences import UserPreferences  # noqa: F401
from app.repositories.prompts import PromptRepository
from app.services.account_deletion import AccountDeletionService
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

REPO_ROOT = Path(__file__).resolve().parents[2]
OPENAPI_PATH = REPO_ROOT / "api" / "openapi" / "openapi.yaml"

requires_postgres = pytest.mark.skipif(
    os.environ.get("SKIP_POSTGRES_TESTS") == "1",
    reason="SKIP_POSTGRES_TESTS=1",
)


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

    def expand(node: object) -> object:
        if isinstance(node, dict):
            if "$ref" in node and isinstance(node["$ref"], str):
                ref = node["$ref"]
                if ref.startswith("#/components/schemas/"):
                    name = ref.rsplit("/", 1)[-1]
                    return expand(openapi_spec["components"]["schemas"][name])
            return {key: expand(value) for key, value in node.items()}
        if isinstance(node, list):
            return [expand(item) for item in node]
        return node

    expanded = expand(schema)
    assert isinstance(expanded, dict)
    Draft202012Validator(expanded).validate(instance)


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
    settings = get_settings().model_copy(
        update={"moderation_operator_token": "test-operator-token"}
    )

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
        http_client.settings = settings  # type: ignore[attr-defined]
        yield http_client

    app.dependency_overrides.clear()
    set_token_verifier(None)


def _auth_headers(client: AsyncClient, *, subject: str | None = None) -> dict[str, str]:
    private_key = client.app.state.test_private_key  # type: ignore[attr-defined]
    token = mint_token(private_key, subject=subject or f"descope|{uuid.uuid4()}")
    return {"Authorization": f"Bearer {token}"}


async def _seed_prompt_on(client: AsyncClient, prompt_date: date) -> DailyPrompt:
    session_factory = client.session_factory  # type: ignore[attr-defined]
    async with session_factory() as session:
        return await PromptRepository(session).upsert_published(
            prompt_date=prompt_date,
            word_1="Chocolate",
            word_2="Coffee",
            word_3="Banana",
            published_at=datetime.combine(prompt_date, datetime.min.time(), tzinfo=UTC),
        )


async def _publish(
    client: AsyncClient,
    headers: dict[str, str],
    *,
    caption: str = "Sketch",
) -> dict[str, Any]:
    today = client.clock.today()  # type: ignore[attr-defined]
    prompt = await _seed_prompt_on(client, today)
    session_id = await _create_ready_session(client, headers, prompt.id)
    upload = await _create_ready_upload(client, headers)
    created = await client.post(
        "/api/v1/submissions",
        headers={**headers, "Idempotency-Key": str(uuid.uuid4())},
        json={
            "sketch_session_id": session_id,
            "upload_id": upload["id"],
            "caption": caption,
        },
    )
    assert created.status_code == 201, created.text
    return created.json()


@requires_postgres
@pytest.mark.asyncio
async def test_block_filters_feed_detail_profile_and_rejects_interactions(
    client: AsyncClient,
    openapi_spec: dict[str, Any],
) -> None:
    alice_headers = _auth_headers(client, subject="descope|alice")
    bob_headers = _auth_headers(client, subject="descope|bob")
    await _complete_profile(client, alice_headers, username="alice_safe")
    bob = await _complete_profile(client, bob_headers, username="bob_safe")
    bob_submission = await _publish(client, bob_headers, caption="Bob art")

    block = await client.put(
        f"/api/v1/users/{bob['id']}/block",
        headers=alice_headers,
    )
    assert block.status_code == 200
    assert_matches_schema(block.json(), "BlockState", openapi_spec)
    assert block.json()["blocked"] is True

    feed = await client.get("/api/v1/feed/recent", headers=alice_headers)
    assert feed.status_code == 200
    assert all(item["id"] != bob_submission["id"] for item in feed.json()["items"])

    detail = await client.get(
        f"/api/v1/submissions/{bob_submission['id']}",
        headers=alice_headers,
    )
    assert detail.status_code == 404

    profile = await client.get("/api/v1/users/bob_safe", headers=alice_headers)
    assert profile.status_code == 404

    like = await client.put(
        f"/api/v1/submissions/{bob_submission['id']}/like",
        headers=alice_headers,
    )
    assert like.status_code in {403, 404}

    blocked_list = await client.get("/api/v1/me/blocked-users", headers=alice_headers)
    assert blocked_list.status_code == 200
    assert_matches_schema(blocked_list.json(), "BlockedUsersResponse", openapi_spec)
    assert len(blocked_list.json()["items"]) == 1
    assert blocked_list.json()["items"][0]["user_id"] == bob["id"]

    # Reciprocal: Bob cannot browse Alice either after Alice blocked him.
    alice_sub = await _publish(client, alice_headers, caption="Alice art")
    bob_sees = await client.get(
        f"/api/v1/submissions/{alice_sub['id']}",
        headers=bob_headers,
    )
    assert bob_sees.status_code == 404

    unblock = await client.delete(
        f"/api/v1/users/{bob['id']}/block",
        headers=alice_headers,
    )
    assert unblock.status_code == 200
    assert unblock.json()["blocked"] is False

    restored = await client.get(
        f"/api/v1/submissions/{bob_submission['id']}",
        headers=alice_headers,
    )
    assert restored.status_code == 200


@requires_postgres
@pytest.mark.asyncio
async def test_cannot_block_self(client: AsyncClient) -> None:
    headers = _auth_headers(client)
    me = await _complete_profile(client, headers, username="self_block")
    response = await client.put(f"/api/v1/users/{me['id']}/block", headers=headers)
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "cannot_block_self"


@requires_postgres
@pytest.mark.asyncio
async def test_report_create_and_dedupe(
    client: AsyncClient,
    openapi_spec: dict[str, Any],
) -> None:
    reporter_headers = _auth_headers(client, subject="descope|reporter")
    target_headers = _auth_headers(client, subject="descope|target")
    await _complete_profile(client, reporter_headers, username="reporter_user")
    await _complete_profile(client, target_headers, username="target_user")
    submission = await _publish(client, target_headers)

    created = await client.post(
        "/api/v1/reports",
        headers=reporter_headers,
        json={
            "target_type": "submission",
            "target_id": submission["id"],
            "reason": "spam",
            "notes": None,
        },
    )
    assert created.status_code == 201, created.text
    assert_matches_schema(created.json(), "ReportResponse", openapi_spec)
    assert "reviewed_by" not in created.json()
    assert "status" not in created.json()

    duplicate = await client.post(
        "/api/v1/reports",
        headers=reporter_headers,
        json={
            "target_type": "submission",
            "target_id": submission["id"],
            "reason": "harassment",
        },
    )
    assert duplicate.status_code in {200, 201, 409}
    if duplicate.status_code in {200, 201}:
        assert duplicate.json()["id"] == created.json()["id"]


@requires_postgres
@pytest.mark.asyncio
async def test_account_deletion_pending_and_finalize(
    client: AsyncClient, openapi_spec: dict[str, Any]
) -> None:
    headers = _auth_headers(client, subject="descope|deleteme")
    profile = await _complete_profile(client, headers, username="delete_me_user")
    submission = await _publish(client, headers, caption="Gone soon")

    deleted = await client.delete("/api/v1/me", headers=headers)
    assert deleted.status_code == 202
    assert_matches_schema(deleted.json(), "AccountDeletionResponse", openapi_spec)
    assert deleted.json()["status"] == "pending_deletion"

    # Idempotent second request.
    again = await client.delete("/api/v1/me", headers=headers)
    assert again.status_code == 202

    public = await client.get("/api/v1/users/delete_me_user")
    assert public.status_code == 404

    feed = await client.get("/api/v1/feed/recent")
    assert feed.status_code == 200
    assert all(item["id"] != submission["id"] for item in feed.json()["items"])

    session_factory = client.session_factory  # type: ignore[attr-defined]
    settings = client.settings  # type: ignore[attr-defined]
    storage = client.storage  # type: ignore[attr-defined]
    clock = client.clock  # type: ignore[attr-defined]
    async with session_factory() as session:
        count = await AccountDeletionService(
            session,
            clock,
            settings=settings,
            storage=storage,
        ).finalize_pending()
        assert count >= 1
        user = (
            await session.execute(select(User).where(User.id == uuid.UUID(profile["id"])))
        ).scalar_one()
        assert user.status == UserStatus.deleted
