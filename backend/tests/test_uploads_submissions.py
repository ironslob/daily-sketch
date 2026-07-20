"""Upload and submission integration, contract, and acceptance tests."""

from __future__ import annotations

import os
import uuid
from collections.abc import AsyncGenerator
from datetime import UTC, date, datetime, timedelta
from io import BytesIO
from pathlib import Path
from typing import Any

import pytest
import yaml
from httpx import ASGITransport, AsyncClient
from jsonschema import Draft202012Validator
from PIL import Image
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.auth.jwt import set_token_verifier
from app.core.clock import Clock, get_clock
from app.core.settings import Settings, get_settings
from app.db.session import Base, get_db_session
from app.main import create_app
from app.models.daily_prompt import DailyPrompt
from app.models.idempotency_key import IdempotencyKey  # noqa: F401
from app.models.sketch_session import SketchSession  # noqa: F401
from app.models.sketch_session_event import SketchSessionEvent  # noqa: F401
from app.models.submission import Submission  # noqa: F401
from app.models.upload import Upload  # noqa: F401
from app.models.user import User  # noqa: F401
from app.models.user_preferences import UserPreferences  # noqa: F401
from app.repositories.prompts import PromptRepository
from app.storage.base import get_storage_adapter
from fake_storage import InMemoryStorageAdapter
from jwt_helpers import StaticTokenVerifier, generate_rsa_keypair, mint_token

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


def make_jpeg(width: int = 100, height: int = 80) -> bytes:
    buf = BytesIO()
    Image.new("RGB", (width, height), color=(200, 100, 50)).save(buf, format="JPEG")
    return buf.getvalue()


async def _complete_profile(
    client: AsyncClient,
    headers: dict[str, str],
    *,
    username: str | None = None,
) -> dict[str, Any]:
    suffix = uuid.uuid4().hex[:8]
    response = await client.patch(
        "/api/v1/me",
        headers=headers,
        json={
            "username": username or f"user_{suffix}",
            "display_name": "Test User",
        },
    )
    assert response.status_code == 200
    return response.json()


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


async def _create_ready_session(
    client: AsyncClient,
    headers: dict[str, str],
    prompt_id: uuid.UUID,
    *,
    idempotency_key: str | None = None,
) -> str:
    create_headers = dict(headers)
    if idempotency_key is not None:
        create_headers["Idempotency-Key"] = idempotency_key
    created = await client.post(
        "/api/v1/sketch-sessions",
        headers=create_headers,
        json={
            "prompt_id": str(prompt_id),
            "timer_mode": "countdown",
            "selected_timer_seconds": 300,
        },
    )
    assert created.status_code == 201
    session_id = created.json()["id"]
    finished = await client.post(
        f"/api/v1/sketch-sessions/{session_id}/events",
        headers=headers,
        json={"event_type": "finished_early"},
    )
    assert finished.status_code == 200
    assert finished.json()["status"] == "ready_for_photo"
    return session_id


async def _put_upload_bytes(
    client: AsyncClient,
    headers: dict[str, str],
    upload_id: str,
    jpeg_bytes: bytes,
) -> None:
    me = await client.get("/api/v1/me", headers=headers)
    assert me.status_code == 200
    user_id = me.json()["id"]
    key = f"users/{user_id}/uploads/{upload_id}/original"
    storage: InMemoryStorageAdapter = client.storage  # type: ignore[attr-defined]
    storage.put_bytes(key, jpeg_bytes, "image/jpeg")


async def _create_ready_upload(
    client: AsyncClient,
    headers: dict[str, str],
    *,
    jpeg_bytes: bytes | None = None,
) -> dict[str, Any]:
    data = jpeg_bytes if jpeg_bytes is not None else make_jpeg()
    created = await client.post(
        "/api/v1/uploads",
        headers=headers,
        json={
            "purpose": "submission",
            "content_type": "image/jpeg",
            "byte_size": len(data),
        },
    )
    assert created.status_code == 201
    upload = created.json()
    assert upload["status"] == "pending"
    assert upload["signed_upload"] is not None
    await _put_upload_bytes(client, headers, upload["id"], data)
    completed = await client.post(
        f"/api/v1/uploads/{upload['id']}/complete",
        headers=headers,
    )
    assert completed.status_code == 200
    body = completed.json()
    assert body["status"] == "ready"
    return body


@requires_postgres
@pytest.mark.asyncio
async def test_invalid_mime_rejected(client: AsyncClient) -> None:
    headers = _auth_headers(client)
    await _complete_profile(client, headers)
    response = await client.post(
        "/api/v1/uploads",
        headers=headers,
        json={
            "purpose": "submission",
            "content_type": "text/plain",
            "byte_size": 128,
        },
    )
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "unsupported_media_type"


@requires_postgres
@pytest.mark.asyncio
async def test_oversized_image_rejected(client: AsyncClient) -> None:
    headers = _auth_headers(client)
    await _complete_profile(client, headers)
    settings: Settings = client.settings  # type: ignore[attr-defined]
    response = await client.post(
        "/api/v1/uploads",
        headers=headers,
        json={
            "purpose": "submission",
            "content_type": "image/jpeg",
            "byte_size": settings.max_upload_bytes + 1,
        },
    )
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "image_too_large"


@requires_postgres
@pytest.mark.asyncio
async def test_object_missing_rejected(client: AsyncClient) -> None:
    headers = _auth_headers(client)
    await _complete_profile(client, headers)
    jpeg = make_jpeg()
    created = await client.post(
        "/api/v1/uploads",
        headers=headers,
        json={
            "purpose": "submission",
            "content_type": "image/jpeg",
            "byte_size": len(jpeg),
        },
    )
    assert created.status_code == 201
    upload_id = created.json()["id"]

    complete = await client.post(
        f"/api/v1/uploads/{upload_id}/complete",
        headers=headers,
    )
    assert complete.status_code == 422
    assert complete.json()["error"]["code"] == "object_missing"


@requires_postgres
@pytest.mark.asyncio
async def test_upload_cannot_be_consumed_twice(client: AsyncClient) -> None:
    headers = _auth_headers(client)
    await _complete_profile(client, headers)
    prompt = await _seed_prompt(client)
    session_id = await _create_ready_session(
        client, headers, prompt.id, idempotency_key="consume-session-1"
    )
    upload = await _create_ready_upload(client, headers)

    first = await client.post(
        "/api/v1/submissions",
        headers={**headers, "Idempotency-Key": "consume-sub-1"},
        json={
            "sketch_session_id": session_id,
            "upload_id": upload["id"],
            "caption": "First publish",
        },
    )
    assert first.status_code == 201

    second_session = await _create_ready_session(
        client, headers, prompt.id, idempotency_key="consume-session-2"
    )
    second = await client.post(
        "/api/v1/submissions",
        headers={**headers, "Idempotency-Key": "consume-sub-2"},
        json={
            "sketch_session_id": second_session,
            "upload_id": upload["id"],
            "caption": "Reuse upload",
        },
    )
    assert second.status_code == 409
    assert second.json()["error"]["code"] in {
        "upload_already_consumed",
        "session_already_submitted",
    }


@requires_postgres
@pytest.mark.asyncio
async def test_another_user_cannot_consume_upload(client: AsyncClient) -> None:
    owner_headers = _auth_headers(client, subject=f"descope|{uuid.uuid4()}")
    other_headers = _auth_headers(client, subject=f"descope|{uuid.uuid4()}")
    await _complete_profile(client, owner_headers, username=f"owner_{uuid.uuid4().hex[:8]}")
    await _complete_profile(client, other_headers, username=f"other_{uuid.uuid4().hex[:8]}")

    prompt = await _seed_prompt(client)
    session_id = await _create_ready_session(
        client, owner_headers, prompt.id, idempotency_key="owner-session"
    )
    upload = await _create_ready_upload(client, owner_headers)
    upload_id = upload["id"]

    other_get = await client.get(f"/api/v1/uploads/{upload_id}", headers=other_headers)
    assert other_get.status_code == 404
    assert other_get.json()["error"]["code"] == "upload_not_found"

    other_complete = await client.post(
        f"/api/v1/uploads/{upload_id}/complete",
        headers=other_headers,
    )
    assert other_complete.status_code == 404
    assert other_complete.json()["error"]["code"] == "upload_not_found"

    other_submit = await client.post(
        "/api/v1/submissions",
        headers=other_headers,
        json={
            "sketch_session_id": session_id,
            "upload_id": upload_id,
        },
    )
    assert other_submit.status_code == 404
    assert other_submit.json()["error"]["code"] in {
        "upload_not_found",
        "session_not_found",
    }


@requires_postgres
@pytest.mark.asyncio
async def test_duplicate_submission_idempotency_key_returns_same_result(
    client: AsyncClient,
) -> None:
    headers = _auth_headers(client)
    await _complete_profile(client, headers)
    prompt = await _seed_prompt(client)
    session_id = await _create_ready_session(client, headers, prompt.id)
    upload = await _create_ready_upload(client, headers)
    payload = {
        "sketch_session_id": session_id,
        "upload_id": upload["id"],
        "caption": "Idempotent caption",
    }

    first = await client.post(
        "/api/v1/submissions",
        headers={**headers, "Idempotency-Key": "sub-dup-1"},
        json=payload,
    )
    second = await client.post(
        "/api/v1/submissions",
        headers={**headers, "Idempotency-Key": "sub-dup-1"},
        json=payload,
    )
    assert first.status_code == 201
    assert second.status_code == 201
    assert first.json()["id"] == second.json()["id"]


@requires_postgres
@pytest.mark.asyncio
async def test_upload_retry_complete_when_ready(client: AsyncClient) -> None:
    headers = _auth_headers(client)
    await _complete_profile(client, headers)
    jpeg = make_jpeg()
    created = await client.post(
        "/api/v1/uploads",
        headers=headers,
        json={
            "purpose": "submission",
            "content_type": "image/jpeg",
            "byte_size": len(jpeg),
        },
    )
    assert created.status_code == 201
    upload_id = created.json()["id"]
    await _put_upload_bytes(client, headers, upload_id, jpeg)

    first = await client.post(f"/api/v1/uploads/{upload_id}/complete", headers=headers)
    assert first.status_code == 200
    assert first.json()["status"] == "ready"

    second = await client.post(f"/api/v1/uploads/{upload_id}/complete", headers=headers)
    assert second.status_code == 200
    assert second.json()["status"] == "ready"
    assert second.json()["id"] == first.json()["id"]


@requires_postgres
@pytest.mark.asyncio
async def test_refresh_signed_upload_for_pending_slot(client: AsyncClient) -> None:
    headers = _auth_headers(client)
    await _complete_profile(client, headers)
    jpeg = make_jpeg()
    created = await client.post(
        "/api/v1/uploads",
        headers={**headers, "Idempotency-Key": "refresh-slot-1"},
        json={
            "purpose": "submission",
            "content_type": "image/jpeg",
            "byte_size": len(jpeg),
        },
    )
    assert created.status_code == 201
    body = created.json()
    upload_id = body["id"]

    refreshed = await client.post(
        f"/api/v1/uploads/{upload_id}/refresh-signed-upload",
        headers=headers,
    )
    assert refreshed.status_code == 200
    refreshed_body = refreshed.json()
    assert refreshed_body["id"] == upload_id
    assert refreshed_body["status"] == "pending"
    assert refreshed_body["signed_upload"]["url"]
    assert refreshed_body["signed_upload"]["method"] == "PUT"
    assert refreshed_body["expires_at"] >= body["expires_at"]

    await _put_upload_bytes(client, headers, upload_id, jpeg)
    completed = await client.post(f"/api/v1/uploads/{upload_id}/complete", headers=headers)
    assert completed.status_code == 200
    assert completed.json()["status"] == "ready"

    ready_refresh = await client.post(
        f"/api/v1/uploads/{upload_id}/refresh-signed-upload",
        headers=headers,
    )
    assert ready_refresh.status_code == 422


@requires_postgres
@pytest.mark.asyncio
async def test_multiple_submissions_for_same_prompt(client: AsyncClient) -> None:
    headers = _auth_headers(client)
    await _complete_profile(client, headers)
    prompt = await _seed_prompt(client)

    session_a = await _create_ready_session(
        client, headers, prompt.id, idempotency_key="multi-session-a"
    )
    upload_a = await _create_ready_upload(client, headers)
    sub_a = await client.post(
        "/api/v1/submissions",
        headers={**headers, "Idempotency-Key": "multi-sub-a"},
        json={"sketch_session_id": session_a, "upload_id": upload_a["id"]},
    )
    assert sub_a.status_code == 201

    session_b = await _create_ready_session(
        client, headers, prompt.id, idempotency_key="multi-session-b"
    )
    upload_b = await _create_ready_upload(client, headers)
    sub_b = await client.post(
        "/api/v1/submissions",
        headers={**headers, "Idempotency-Key": "multi-sub-b"},
        json={"sketch_session_id": session_b, "upload_id": upload_b["id"]},
    )
    assert sub_b.status_code == 201
    assert sub_a.json()["id"] != sub_b.json()["id"]
    assert sub_a.json()["prompt"]["id"] == sub_b.json()["prompt"]["id"] == str(prompt.id)


@requires_postgres
@pytest.mark.asyncio
async def test_delete_hides_submission(client: AsyncClient) -> None:
    headers = _auth_headers(client)
    await _complete_profile(client, headers)
    prompt = await _seed_prompt(client)
    session_id = await _create_ready_session(client, headers, prompt.id)
    upload = await _create_ready_upload(client, headers)
    created = await client.post(
        "/api/v1/submissions",
        headers=headers,
        json={"sketch_session_id": session_id, "upload_id": upload["id"]},
    )
    assert created.status_code == 201
    submission_id = created.json()["id"]
    body = created.json()
    assert "/display" in body["image_url"] or "display" in body["image_url"]
    assert "/thumbnail" in body["thumbnail_url"] or "thumbnail" in body["thumbnail_url"]
    assert "/original" not in body["image_url"]
    assert "/original" not in body["thumbnail_url"]

    fetched = await client.get(f"/api/v1/submissions/{submission_id}", headers=headers)
    assert fetched.status_code == 200
    assert "/original" not in fetched.json()["image_url"]

    deleted = await client.delete(f"/api/v1/submissions/{submission_id}", headers=headers)
    assert deleted.status_code == 204

    after = await client.get(f"/api/v1/submissions/{submission_id}", headers=headers)
    assert after.status_code == 404
    assert after.json()["error"]["code"] == "submission_not_found"


@requires_postgres
@pytest.mark.asyncio
async def test_profile_incomplete_cannot_publish(client: AsyncClient) -> None:
    headers = _auth_headers(client)
    # Ensure the user row exists without completing the profile.
    me = await client.get("/api/v1/me", headers=headers)
    assert me.status_code == 200
    assert me.json()["profile_completed"] is False

    prompt = await _seed_prompt(client)
    session_id = await _create_ready_session(client, headers, prompt.id)
    upload = await _create_ready_upload(client, headers)

    response = await client.post(
        "/api/v1/submissions",
        headers=headers,
        json={"sketch_session_id": session_id, "upload_id": upload["id"]},
    )
    assert response.status_code == 403
    assert response.json()["error"]["code"] == "profile_incomplete"


@requires_postgres
@pytest.mark.asyncio
async def test_upload_and_submission_openapi_contract(
    client: AsyncClient,
    openapi_spec: dict[str, Any],
) -> None:
    headers = _auth_headers(client)
    await _complete_profile(client, headers)
    prompt = await _seed_prompt(client)
    session_id = await _create_ready_session(client, headers, prompt.id)
    jpeg = make_jpeg()

    created_upload = await client.post(
        "/api/v1/uploads",
        headers=headers,
        json={
            "purpose": "submission",
            "content_type": "image/jpeg",
            "byte_size": len(jpeg),
        },
    )
    assert created_upload.status_code == 201
    upload_body = created_upload.json()
    assert_matches_schema(upload_body, "Upload", openapi_spec)
    assert upload_body["signed_upload"] is not None

    await _put_upload_bytes(client, headers, upload_body["id"], jpeg)
    completed = await client.post(
        f"/api/v1/uploads/{upload_body['id']}/complete",
        headers=headers,
    )
    assert completed.status_code == 200
    complete_body = completed.json()
    assert_matches_schema(complete_body, "Upload", openapi_spec)
    assert complete_body["status"] == "ready"
    assert complete_body["width"] == 100
    assert complete_body["height"] == 80

    submission = await client.post(
        "/api/v1/submissions",
        headers=headers,
        json={
            "sketch_session_id": session_id,
            "upload_id": upload_body["id"],
            "caption": "Contract sketch",
        },
    )
    assert submission.status_code == 201
    submission_body = submission.json()
    assert_matches_schema(submission_body, "Submission", openapi_spec)
    assert submission_body["status"] == "published"
    assert submission_body["is_owner"] is True
