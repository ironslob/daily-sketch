"""Async SQLAlchemy engine and session helpers."""

from collections.abc import AsyncGenerator

from sqlalchemy.ext.asyncio import (
    AsyncEngine,
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)
from sqlalchemy.orm import DeclarativeBase

from app.core.settings import Settings, get_settings


class Base(DeclarativeBase):
    """Declarative base for ORM models."""


def _connect_args(settings: Settings) -> dict[str, object]:
    args: dict[str, object] = {
        "server_settings": {
            "statement_timeout": str(settings.db_statement_timeout_ms),
        }
    }
    if settings.db_ssl_require:
        args["ssl"] = True
    return args


def create_engine(settings: Settings | None = None) -> AsyncEngine:
    resolved = settings or get_settings()
    return create_async_engine(
        resolved.database_url,
        pool_pre_ping=True,
        pool_size=resolved.db_pool_size,
        max_overflow=resolved.db_max_overflow,
        pool_timeout=resolved.db_pool_timeout_seconds,
        pool_recycle=resolved.db_pool_recycle_seconds,
        connect_args=_connect_args(resolved),
    )


engine: AsyncEngine = create_engine()
SessionLocal = async_sessionmaker(engine, expire_on_commit=False, class_=AsyncSession)


async def get_db_session() -> AsyncGenerator[AsyncSession]:
    async with SessionLocal() as session:
        yield session
