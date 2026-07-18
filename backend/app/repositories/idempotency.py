"""Idempotency key persistence helpers."""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Any

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.idempotency_key import IdempotencyKey


class IdempotencyRepository:
    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def get(
        self,
        *,
        user_id: uuid.UUID,
        endpoint: str,
        key: str,
    ) -> IdempotencyKey | None:
        result = await self._session.execute(
            select(IdempotencyKey).where(
                IdempotencyKey.user_id == user_id,
                IdempotencyKey.endpoint == endpoint,
                IdempotencyKey.key == key,
            )
        )
        return result.scalar_one_or_none()

    async def put(
        self,
        *,
        user_id: uuid.UUID,
        endpoint: str,
        key: str,
        request_hash: str,
        response_status: int,
        response_body: dict[str, Any],
        expires_at: datetime,
    ) -> IdempotencyKey:
        record = IdempotencyKey(
            id=uuid.uuid4(),
            user_id=user_id,
            endpoint=endpoint,
            key=key,
            request_hash=request_hash,
            response_status=response_status,
            response_body=response_body,
            expires_at=expires_at,
        )
        self._session.add(record)
        await self._session.commit()
        await self._session.refresh(record)
        return record
