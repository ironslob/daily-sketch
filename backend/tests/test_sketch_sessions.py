"""Sketch Session integration, contract, and unit tests."""

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
from jwt_helpers import StaticTokenVerifier, generate_rsa_keypair, mint_token
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.auth.jwt import set_token_verifier
from app.core.clock import Clock, get_clock
from app.core.errors import AppError
from app.db.session import Base, get_db_session
from app.main import create_app
from app.models.daily_prompt import DailyPrompt
from app.models.enums import TimerMode
from app.models.idempotency_key import IdempotencyKey  # noqa: F401
from app.models.sketch_session import SketchSession  # noqa: F401
from app.models.sketch_session_event import SketchSessionEvent  # noqa: F401
from app.models.user import User  # noqa: F401
from app.models.user_preferences import UserPreferences  # noqa: F401
from app.repositories.prompts import PromptRepository
from app.services.sketch_sessions import validate_timer_selection

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

    app = create_app()
    app.state.token_verifier = verifier
    app.state.test_private_key = private_key

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
    set_token_verifier(None)


def _auth_headers(client: AsyncClient, *, subject: str | None = None) -> dict[str, str]:
    private_key = client.app.state.test_private_key  # type: ignore[attr-defined]
    token = mint_token(private_key, subject=subject or f"descope|{uuid.uuid4()}")
    return {"Authorization": f"Bearer {token}"}


async def _seed_prompt(client: AsyncClient) -> DailyPrompt:
    session_factory = client.session_factory  # type: ignore[attr-defined]
    async with session_factory() as session:
        return await PromptRepository(session).upsert_published(
            prompt_date=date(2026, 7, 18),
            word_1="Chocolate",
            word_2="Coffee",
            word_3="Banana",
            published_at=datetime(2026, 7, 17, tzinfo=UTC),
        )


def test_validate_timer_selection_accepts_allowed_values() -> None:
    validate_timer_selection(TimerMode.countdown, 60)
    validate_timer_selection(TimerMode.countdown, 180)
    validate_timer_selection(TimerMode.countdown, 300)
    validate_timer_selection(TimerMode.countdown, 600)
    validate_timer_selection(TimerMode.no_timer, None)


def test_validate_timer_selection_rejects_invalid_values() -> None:
    with pytest.raises(AppError) as countdown_exc:
        validate_timer_selection(TimerMode.countdown, 120)
    assert countdown_exc.value.code == "invalid_timer_selection"

    with pytest.raises(AppError) as no_timer_exc:
        validate_timer_selection(TimerMode.no_timer, 300)
    assert no_timer_exc.value.code == "invalid_timer_selection"

    with pytest.raises(AppError) as missing_exc:
        validate_timer_selection(TimerMode.countdown, None)
    assert missing_exc.value.code == "invalid_timer_selection"


@requires_postgres
@pytest.mark.asyncio
async def test_create_get_events_abandon_happy_path(
    client: AsyncClient,
    openapi_spec: dict[str, Any],
) -> None:
    prompt = await _seed_prompt(client)
    headers = _auth_headers(client)

    create = await client.post(
        "/api/v1/sketch-sessions",
        headers={**headers, "Idempotency-Key": "create-happy-1"},
        json={
            "prompt_id": str(prompt.id),
            "timer_mode": "countdown",
            "selected_timer_seconds": 300,
            "client_timezone": "Europe/London",
            "client_session_id": "local-1",
        },
    )
    assert create.status_code == 201
    body = create.json()
    assert_matches_schema(body, "SketchSession", openapi_spec)
    assert body["status"] == "active"
    assert body["paused_total_seconds"] == 0
    session_id = body["id"]

    fetched = await client.get(f"/api/v1/sketch-sessions/{session_id}", headers=headers)
    assert fetched.status_code == 200
    assert_matches_schema(fetched.json(), "SketchSession", openapi_spec)

    paused = await client.post(
        f"/api/v1/sketch-sessions/{session_id}/events",
        headers=headers,
        json={"event_type": "paused"},
    )
    assert paused.status_code == 200
    assert paused.json()["status"] == "paused"

    client.clock.advance(seconds=45)  # type: ignore[attr-defined]
    resumed = await client.post(
        f"/api/v1/sketch-sessions/{session_id}/events",
        headers=headers,
        json={"event_type": "resumed"},
    )
    assert resumed.status_code == 200
    assert resumed.json()["status"] == "active"
    assert resumed.json()["paused_total_seconds"] == 45

    finished = await client.post(
        f"/api/v1/sketch-sessions/{session_id}/events",
        headers=headers,
        json={"event_type": "finished_early"},
    )
    assert finished.status_code == 200
    assert finished.json()["status"] == "ready_for_photo"
    assert finished.json()["finish_requested_at"] is not None

    # Create another session to abandon while active.
    other = await client.post(
        "/api/v1/sketch-sessions",
        headers={**headers, "Idempotency-Key": "create-happy-2"},
        json={
            "prompt_id": str(prompt.id),
            "timer_mode": "no_timer",
            "selected_timer_seconds": None,
        },
    )
    assert other.status_code == 201
    other_id = other.json()["id"]
    abandoned = await client.post(
        f"/api/v1/sketch-sessions/{other_id}/abandon",
        headers=headers,
    )
    assert abandoned.status_code == 200
    assert abandoned.json()["status"] == "abandoned"
    assert abandoned.json()["abandoned_at"] is not None

    # Abandon is idempotent.
    abandoned_again = await client.post(
        f"/api/v1/sketch-sessions/{other_id}/abandon",
        headers=headers,
    )
    assert abandoned_again.status_code == 200
    assert abandoned_again.json()["status"] == "abandoned"


@requires_postgres
@pytest.mark.asyncio
async def test_idempotent_create_returns_same_session(client: AsyncClient) -> None:
    prompt = await _seed_prompt(client)
    headers = _auth_headers(client)
    payload = {
        "prompt_id": str(prompt.id),
        "timer_mode": "countdown",
        "selected_timer_seconds": 180,
    }

    first = await client.post(
        "/api/v1/sketch-sessions",
        headers={**headers, "Idempotency-Key": "dup-key-1"},
        json=payload,
    )
    second = await client.post(
        "/api/v1/sketch-sessions",
        headers={**headers, "Idempotency-Key": "dup-key-1"},
        json=payload,
    )
    assert first.status_code == 201
    assert second.status_code == 201
    assert first.json()["id"] == second.json()["id"]


@requires_postgres
@pytest.mark.asyncio
async def test_idempotency_key_conflict(client: AsyncClient) -> None:
    prompt = await _seed_prompt(client)
    headers = _auth_headers(client)
    first = await client.post(
        "/api/v1/sketch-sessions",
        headers={**headers, "Idempotency-Key": "conflict-key"},
        json={
            "prompt_id": str(prompt.id),
            "timer_mode": "countdown",
            "selected_timer_seconds": 60,
        },
    )
    assert first.status_code == 201

    conflict = await client.post(
        "/api/v1/sketch-sessions",
        headers={**headers, "Idempotency-Key": "conflict-key"},
        json={
            "prompt_id": str(prompt.id),
            "timer_mode": "no_timer",
            "selected_timer_seconds": None,
        },
    )
    assert conflict.status_code == 409
    assert conflict.json()["error"]["code"] == "idempotency_key_conflict"


@requires_postgres
@pytest.mark.asyncio
async def test_invalid_duration_rejected(client: AsyncClient) -> None:
    prompt = await _seed_prompt(client)
    headers = _auth_headers(client)
    response = await client.post(
        "/api/v1/sketch-sessions",
        headers=headers,
        json={
            "prompt_id": str(prompt.id),
            "timer_mode": "countdown",
            "selected_timer_seconds": 90,
        },
    )
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "invalid_timer_selection"


@requires_postgres
@pytest.mark.asyncio
async def test_no_timer_create_valid(client: AsyncClient, openapi_spec: dict[str, Any]) -> None:
    prompt = await _seed_prompt(client)
    headers = _auth_headers(client)
    response = await client.post(
        "/api/v1/sketch-sessions",
        headers=headers,
        json={
            "prompt_id": str(prompt.id),
            "timer_mode": "no_timer",
            "selected_timer_seconds": None,
        },
    )
    assert response.status_code == 201
    body = response.json()
    assert_matches_schema(body, "SketchSession", openapi_spec)
    assert body["timer_mode"] == "no_timer"
    assert body["selected_timer_seconds"] is None


@requires_postgres
@pytest.mark.asyncio
async def test_transition_rules_enforced(client: AsyncClient) -> None:
    prompt = await _seed_prompt(client)
    headers = _auth_headers(client)
    created = await client.post(
        "/api/v1/sketch-sessions",
        headers=headers,
        json={
            "prompt_id": str(prompt.id),
            "timer_mode": "countdown",
            "selected_timer_seconds": 300,
        },
    )
    session_id = created.json()["id"]

    resume_without_pause = await client.post(
        f"/api/v1/sketch-sessions/{session_id}/events",
        headers=headers,
        json={"event_type": "resumed"},
    )
    assert resume_without_pause.status_code == 422
    assert resume_without_pause.json()["error"]["code"] == "invalid_session_transition"

    await client.post(f"/api/v1/sketch-sessions/{session_id}/abandon", headers=headers)
    event_on_abandoned = await client.post(
        f"/api/v1/sketch-sessions/{session_id}/events",
        headers=headers,
        json={"event_type": "paused"},
    )
    assert event_on_abandoned.status_code == 422
    assert event_on_abandoned.json()["error"]["code"] == "invalid_session_transition"


@requires_postgres
@pytest.mark.asyncio
async def test_ownership_enforced(client: AsyncClient) -> None:
    prompt = await _seed_prompt(client)
    owner_headers = _auth_headers(client, subject=f"descope|{uuid.uuid4()}")
    other_headers = _auth_headers(client, subject=f"descope|{uuid.uuid4()}")

    created = await client.post(
        "/api/v1/sketch-sessions",
        headers=owner_headers,
        json={
            "prompt_id": str(prompt.id),
            "timer_mode": "countdown",
            "selected_timer_seconds": 60,
        },
    )
    session_id = created.json()["id"]

    other_get = await client.get(
        f"/api/v1/sketch-sessions/{session_id}",
        headers=other_headers,
    )
    assert other_get.status_code == 404
    assert other_get.json()["error"]["code"] == "session_not_found"

    missing = await client.get(
        f"/api/v1/sketch-sessions/{uuid.uuid4()}",
        headers=owner_headers,
    )
    assert missing.status_code == 404
    assert missing.json()["error"]["code"] == "session_not_found"


@requires_postgres
@pytest.mark.asyncio
async def test_timer_completed_sets_ready_for_photo(client: AsyncClient) -> None:
    prompt = await _seed_prompt(client)
    headers = _auth_headers(client)
    created = await client.post(
        "/api/v1/sketch-sessions",
        headers=headers,
        json={
            "prompt_id": str(prompt.id),
            "timer_mode": "countdown",
            "selected_timer_seconds": 60,
        },
    )
    session_id = created.json()["id"]
    completed = await client.post(
        f"/api/v1/sketch-sessions/{session_id}/events",
        headers=headers,
        json={"event_type": "timer_completed"},
    )
    assert completed.status_code == 200
    assert completed.json()["status"] == "ready_for_photo"
    assert completed.json()["timer_completed_at"] is not None
