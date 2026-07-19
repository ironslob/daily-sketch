"""Community feed integration and contract tests."""

from __future__ import annotations

import os
import uuid
from collections.abc import AsyncGenerator
from datetime import UTC, date, datetime, timedelta
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
from app.models.sketch_session import SketchSession  # noqa: F401
from app.models.sketch_session_event import SketchSessionEvent  # noqa: F401
from app.models.submission import Submission  # noqa: F401
from app.models.upload import Upload  # noqa: F401
from app.models.user import User, UserStatus
from app.models.user_preferences import UserPreferences  # noqa: F401
from app.services.feed import caption_preview
from app.storage.base import get_storage_adapter
from fake_storage import InMemoryStorageAdapter
from jwt_helpers import StaticTokenVerifier, generate_rsa_keypair, mint_token
from test_uploads_submissions import (
    _complete_profile,
    _create_ready_session,
    _create_ready_upload,
    _seed_prompt,
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


class FixedClock:
    def __init__(self, instant: datetime) -> None:
        self._instant = instant

    def now(self) -> datetime:
        return self._instant

    def today(self) -> date:
        return self._instant.date()

    def advance(self, **kwargs: Any) -> None:
        self._instant = self._instant + timedelta(**kwargs)


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
    clock = FixedClock(datetime(2026, 7, 18, 20, 0, tzinfo=UTC))
    session_factory = async_sessionmaker(db_engine, expire_on_commit=False, class_=AsyncSession)
    fake_storage = InMemoryStorageAdapter()
    settings = get_settings()

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


async def _publish_submission(
    client: AsyncClient,
    *,
    subject: str | None = None,
    username: str | None = None,
    caption: str | None = "A quiet sketch.",
    advance_seconds: int = 0,
) -> dict[str, Any]:
    headers = _auth_headers(client, subject=subject)
    await _complete_profile(client, headers, username=username)
    prompt = await _seed_prompt(client)
    if advance_seconds:
        client.clock.advance(seconds=advance_seconds)  # type: ignore[attr-defined]
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
    return {"headers": headers, "submission": created.json()}


@requires_postgres
@pytest.mark.asyncio
async def test_feed_orders_newest_first_and_matches_contract(
    client: AsyncClient,
    openapi_spec: dict[str, Any],
) -> None:
    first = await _publish_submission(
        client,
        username="first_user",
        caption="First sketch",
    )
    second = await _publish_submission(
        client,
        username="second_user",
        caption="Second sketch",
        advance_seconds=30,
    )

    response = await client.get("/api/v1/feed/recent")
    assert response.status_code == 200
    body = response.json()
    assert_matches_schema(body, "RecentFeed", openapi_spec)
    assert len(body["items"]) == 2
    assert body["items"][0]["id"] == second["submission"]["id"]
    assert body["items"][1]["id"] == first["submission"]["id"]
    assert body["next_cursor"] is None

    lead = body["items"][0]
    assert lead["caption_preview"] == "Second sketch"
    assert lead["like_count"] == 0
    assert lead["reflection_count"] == 0
    assert lead["viewer_has_liked"] is False
    assert lead["is_owner"] is False
    assert lead["image_url"]
    assert lead["thumbnail_url"]
    assert lead["user"]["username"] == "second_user"
    assert lead["prompt"]["word_1"] == "Chocolate"
    assert_matches_schema(lead, "FeedItem", openapi_spec)


@requires_postgres
@pytest.mark.asyncio
async def test_feed_cursor_pagination_stable_under_new_inserts(
    client: AsyncClient,
) -> None:
    published_ids: list[str] = []
    for index in range(3):
        result = await _publish_submission(
            client,
            username=f"pager_{index}",
            caption=f"Sketch {index}",
            advance_seconds=index * 10,
        )
        published_ids.append(result["submission"]["id"])

    first_page = await client.get("/api/v1/feed/recent", params={"limit": 2})
    assert first_page.status_code == 200
    first_body = first_page.json()
    assert len(first_body["items"]) == 2
    assert first_body["next_cursor"] is not None
    first_ids = [item["id"] for item in first_body["items"]]

    newer = await _publish_submission(
        client,
        username="pager_new",
        caption="Inserted later",
        advance_seconds=100,
    )

    second_page = await client.get(
        "/api/v1/feed/recent",
        params={"limit": 2, "cursor": first_body["next_cursor"]},
    )
    assert second_page.status_code == 200
    second_body = second_page.json()
    second_ids = [item["id"] for item in second_body["items"]]

    assert set(first_ids).isdisjoint(second_ids)
    assert newer["submission"]["id"] not in second_ids
    assert published_ids[0] in second_ids


@requires_postgres
@pytest.mark.asyncio
async def test_feed_excludes_deleted_and_suspended_authors(client: AsyncClient) -> None:
    kept = await _publish_submission(client, username="kept_user", caption="Keep me")
    deleted = await _publish_submission(
        client,
        username="deleted_user",
        caption="Delete me",
        advance_seconds=20,
    )
    suspended = await _publish_submission(
        client,
        username="suspended_user",
        caption="Suspend me",
        advance_seconds=40,
    )

    delete_response = await client.delete(
        f"/api/v1/submissions/{deleted['submission']['id']}",
        headers=deleted["headers"],
    )
    assert delete_response.status_code == 204

    session_factory = client.session_factory  # type: ignore[attr-defined]
    async with session_factory() as session:
        user = (
            await session.execute(select(User).where(User.username == "suspended_user"))
        ).scalar_one()
        user.status = UserStatus.suspended
        await session.commit()

    response = await client.get("/api/v1/feed/recent")
    assert response.status_code == 200
    ids = [item["id"] for item in response.json()["items"]]
    assert ids == [kept["submission"]["id"]]

    detail = await client.get(f"/api/v1/submissions/{suspended['submission']['id']}")
    assert detail.status_code == 404
    assert detail.json()["error"]["code"] == "submission_not_found"

    deleted_detail = await client.get(f"/api/v1/submissions/{deleted['submission']['id']}")
    assert deleted_detail.status_code == 404


@requires_postgres
@pytest.mark.asyncio
async def test_feed_owner_flag_for_authenticated_viewer(client: AsyncClient) -> None:
    owned = await _publish_submission(client, username="owner_user", caption="Mine")
    await _publish_submission(
        client,
        username="other_user",
        caption="Theirs",
        advance_seconds=15,
    )

    response = await client.get("/api/v1/feed/recent", headers=owned["headers"])
    assert response.status_code == 200
    items = {item["id"]: item for item in response.json()["items"]}
    assert items[owned["submission"]["id"]]["is_owner"] is True
    other_id = next(id_ for id_ in items if id_ != owned["submission"]["id"])
    assert items[other_id]["is_owner"] is False


@requires_postgres
@pytest.mark.asyncio
async def test_owner_delete_removes_from_feed_and_detail(client: AsyncClient) -> None:
    published = await _publish_submission(client, username="deleter", caption="Gone soon")
    submission_id = published["submission"]["id"]

    before = await client.get("/api/v1/feed/recent")
    assert submission_id in [item["id"] for item in before.json()["items"]]

    deleted = await client.delete(
        f"/api/v1/submissions/{submission_id}",
        headers=published["headers"],
    )
    assert deleted.status_code == 204

    after = await client.get("/api/v1/feed/recent")
    assert submission_id not in [item["id"] for item in after.json()["items"]]

    detail = await client.get(f"/api/v1/submissions/{submission_id}")
    assert detail.status_code == 404


def test_caption_preview_truncates() -> None:
    assert caption_preview(None) is None
    assert caption_preview("  ") is None
    assert caption_preview("short") == "short"
    long = "x" * 200
    preview = caption_preview(long)
    assert preview is not None
    assert len(preview) == 140
    assert preview.endswith("…")
