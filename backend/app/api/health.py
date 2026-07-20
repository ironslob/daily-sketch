"""Health check routes."""

from __future__ import annotations

from pathlib import Path

from fastapi import APIRouter, Response, status
from sqlalchemy import text

from app.core.settings import get_settings
from app.db.session import SessionLocal
from app.storage.base import get_storage_adapter

router = APIRouter(tags=["health"])


async def _alembic_revision() -> str | None:
    try:
        async with SessionLocal() as session:
            result = await session.execute(text("SELECT version_num FROM alembic_version LIMIT 1"))
            row = result.first()
            if row is None:
                return None
            return str(row[0])
    except Exception:
        return None


@router.get("/health/live")
async def live() -> dict[str, str]:
    """Liveness probe — process can respond."""
    return {"status": "ok"}


@router.get("/health/version")
async def version() -> dict[str, str | None]:
    """Release metadata for deployment traceability."""
    settings = get_settings()
    openapi_path = Path(__file__).resolve().parents[3] / "api" / "openapi" / "openapi.yaml"
    contract_revision = "unknown"
    if openapi_path.exists():
        contract_revision = openapi_path.name
    return {
        "release_version": settings.release_version,
        "commit_sha": settings.commit_sha,
        "build_timestamp": settings.build_timestamp,
        "environment": settings.app_env,
        "migration_revision": await _alembic_revision(),
        "openapi_contract": contract_revision,
    }


@router.get("/health/ready")
async def ready(response: Response) -> dict[str, object]:
    """Readiness probe — required config, database, and storage connectivity."""
    settings = get_settings()
    checks: dict[str, str] = {}

    if not settings.database_url:
        checks["database"] = "missing_config"
    else:
        try:
            async with SessionLocal() as session:
                await session.execute(text("SELECT 1"))
            checks["database"] = "ok"
        except Exception:  # readiness must not raise for probe endpoints
            checks["database"] = "unavailable"

    if not settings.storage_bucket:
        checks["storage_config"] = "missing_config"
    else:
        checks["storage_config"] = "ok"
        try:
            storage = get_storage_adapter()
            storage_ok = await storage.ping()
            checks["storage"] = "ok" if storage_ok else "unavailable"
        except Exception:
            checks["storage"] = "unavailable"

    healthy = all(value == "ok" for value in checks.values())
    if not healthy:
        response.status_code = status.HTTP_503_SERVICE_UNAVAILABLE

    return {"status": "ok" if healthy else "unavailable", "checks": checks}
