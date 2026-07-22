"""Integration and contract tests for Daily Prompt and empty feed endpoints."""

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
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.core.clock import Clock, get_clock
from app.db.session import Base, get_db_session
from app.main import create_app
from app.models.daily_prompt import DailyPrompt, PromptStatus
from app.models.user import User  # noqa: F401
from app.models.user_preferences import UserPreferences  # noqa: F401
from app.repositories.prompts import PromptRepository, prompt_date_lock_key
from app.seeds.prompts import generate_prompt_words

DATABASE_URL = os.environ.get(
    "DATABASE_URL",
    "postgresql+asyncpg://dailycreative:dailycreative@localhost:5432/dailycreative",  # pragma: allowlist secret
)

REPO_ROOT = Path(__file__).resolve().parents[2]
OPENAPI_PATH = REPO_ROOT / "api" / "openapi" / "openapi.yaml"

requires_postgres = pytest.mark.skipif(
    os.environ.get("SKIP_POSTGRES_TESTS") == "1",
    reason="SKIP_POSTGRES_TESTS=1",
)


class FixedClock:
    """Test clock with a fixed UTC date."""

    def __init__(self, today: date) -> None:
        self._today = today

    def now(self) -> datetime:
        return datetime(self._today.year, self._today.month, self._today.day, tzinfo=UTC)

    def today(self) -> date:
        return self._today


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
    clock = FixedClock(date(2026, 7, 18))
    session_factory = async_sessionmaker(db_engine, expire_on_commit=False, class_=AsyncSession)

    app = create_app()

    async def override_db() -> AsyncGenerator[AsyncSession]:
        async with session_factory() as session:
            yield session

    def override_clock() -> Clock:
        return clock

    app.dependency_overrides[get_db_session] = override_db
    app.dependency_overrides[get_clock] = override_clock

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as http_client:
        http_client.app = app  # type: ignore[attr-defined]
        http_client.clock = clock  # type: ignore[attr-defined]
        http_client.session_factory = session_factory  # type: ignore[attr-defined]
        yield http_client

    app.dependency_overrides.clear()


async def _seed_prompt(
    client: AsyncClient,
    *,
    prompt_date: date = date(2026, 7, 18),
    words: tuple[str, str, str] = ("Chocolate", "Coffee", "Banana"),
    status: PromptStatus = PromptStatus.published,
) -> DailyPrompt:
    session_factory = client.session_factory  # type: ignore[attr-defined]
    async with session_factory() as session:
        if status == PromptStatus.published:
            prompt = await PromptRepository(session).upsert_published(
                prompt_date=prompt_date,
                word_1=words[0],
                word_2=words[1],
                word_3=words[2],
                published_at=datetime(2026, 7, 17, tzinfo=UTC),
            )
            return prompt

        prompt = DailyPrompt(
            id=uuid.uuid4(),
            prompt_date=prompt_date,
            word_1=words[0],
            word_2=words[1],
            word_3=words[2],
            status=status,
            published_at=None,
        )
        session.add(prompt)
        await session.commit()
        await session.refresh(prompt)
        return prompt


@requires_postgres
@pytest.mark.asyncio
async def test_today_returns_published_prompt_preserving_order(
    client: AsyncClient,
    openapi_spec: dict[str, Any],
) -> None:
    await _seed_prompt(client)

    first = await client.get("/api/v1/prompts/today")
    second = await client.get("/api/v1/prompts/today")

    assert first.status_code == 200
    assert second.status_code == 200
    body = first.json()
    assert body == second.json()
    assert body["word_1"] == "Chocolate"
    assert body["word_2"] == "Coffee"
    assert body["word_3"] == "Banana"
    assert body["prompt_date"] == "2026-07-18"
    assert body["status"] == "published"
    assert_matches_schema(body, "DailyPrompt", openapi_spec)


@requires_postgres
@pytest.mark.asyncio
async def test_today_creates_published_prompt_when_missing(
    client: AsyncClient,
    openapi_spec: dict[str, Any],
) -> None:
    expected = generate_prompt_words(date(2026, 7, 18))
    response = await client.get("/api/v1/prompts/today")
    assert response.status_code == 200
    body = response.json()
    assert body["prompt_date"] == "2026-07-18"
    assert body["status"] == "published"
    assert body["word_1"] == expected[0]
    assert body["word_2"] == expected[1]
    assert body["word_3"] == expected[2]
    assert body["published_at"] is not None
    assert_matches_schema(body, "DailyPrompt", openapi_spec)


@requires_postgres
@pytest.mark.asyncio
async def test_today_on_demand_is_idempotent(client: AsyncClient) -> None:
    first = await client.get("/api/v1/prompts/today")
    second = await client.get("/api/v1/prompts/today")
    assert first.status_code == 200
    assert second.status_code == 200
    assert first.json() == second.json()


@requires_postgres
@pytest.mark.asyncio
async def test_today_ignores_draft_prompt(client: AsyncClient) -> None:
    await _seed_prompt(client, status=PromptStatus.draft)
    response = await client.get("/api/v1/prompts/today")
    assert response.status_code == 404
    assert response.json()["error"]["code"] == "prompt_not_found"


@requires_postgres
@pytest.mark.asyncio
async def test_get_prompt_by_id(
    client: AsyncClient,
    openapi_spec: dict[str, Any],
) -> None:
    prompt = await _seed_prompt(client)

    response = await client.get(f"/api/v1/prompts/{prompt.id}")
    assert response.status_code == 200
    body = response.json()
    assert body["id"] == str(prompt.id)
    assert body["word_1"] == "Chocolate"
    assert_matches_schema(body, "DailyPrompt", openapi_spec)

    missing = await client.get(f"/api/v1/prompts/{uuid.uuid4()}")
    assert missing.status_code == 404
    assert missing.json()["error"]["code"] == "prompt_not_found"


@requires_postgres
@pytest.mark.asyncio
async def test_get_prompt_by_id_hides_draft(client: AsyncClient) -> None:
    prompt = await _seed_prompt(client, status=PromptStatus.draft)
    response = await client.get(f"/api/v1/prompts/{prompt.id}")
    assert response.status_code == 404


@requires_postgres
@pytest.mark.asyncio
async def test_one_prompt_per_date_constraint(client: AsyncClient) -> None:
    await _seed_prompt(client, words=("Chocolate", "Coffee", "Banana"))
    # Upsert updates the same date rather than creating a duplicate.
    updated = await _seed_prompt(client, words=("River", "Lantern", "Oak"))
    response = await client.get("/api/v1/prompts/today")
    assert response.status_code == 200
    body = response.json()
    assert body["id"] == str(updated.id)
    assert body["word_1"] == "River"
    assert body["word_2"] == "Lantern"
    assert body["word_3"] == "Oak"


@requires_postgres
@pytest.mark.asyncio
async def test_recent_feed_returns_empty_page(
    client: AsyncClient,
    openapi_spec: dict[str, Any],
) -> None:
    response = await client.get("/api/v1/feed/recent", params={"creative_type": "sketch"})
    assert response.status_code == 200
    body = response.json()
    assert body == {"items": [], "next_cursor": None}
    assert_matches_schema(body, "RecentFeed", openapi_spec)


@requires_postgres
@pytest.mark.asyncio
async def test_recent_feed_rejects_invalid_cursor(client: AsyncClient) -> None:
    response = await client.get(
        "/api/v1/feed/recent", params={"cursor": "abc", "limit": 10, "creative_type": "sketch"}
    )
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "invalid_cursor"


def test_prompt_date_lock_key_is_stable_yyyymmdd() -> None:
    assert prompt_date_lock_key(date(2026, 7, 18)) == 20260718
    assert prompt_date_lock_key(date(2026, 1, 5)) == 20260105
    assert prompt_date_lock_key(date(2026, 7, 18)) == prompt_date_lock_key(date(2026, 7, 18))
    assert prompt_date_lock_key(date(2026, 7, 18)) != prompt_date_lock_key(date(2026, 7, 19))
