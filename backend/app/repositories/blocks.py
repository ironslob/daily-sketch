"""User block repository."""

from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import and_, delete, or_, select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.user import User
from app.models.user_block import UserBlock


class BlockRepository:
    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def exists(self, *, blocker_user_id: uuid.UUID, blocked_user_id: uuid.UUID) -> bool:
        result = await self._session.execute(
            select(UserBlock.blocker_user_id).where(
                UserBlock.blocker_user_id == blocker_user_id,
                UserBlock.blocked_user_id == blocked_user_id,
            )
        )
        return result.scalar_one_or_none() is not None

    async def either_direction_exists(self, *, user_a: uuid.UUID, user_b: uuid.UUID) -> bool:
        result = await self._session.execute(
            select(UserBlock.blocker_user_id).where(
                or_(
                    and_(
                        UserBlock.blocker_user_id == user_a,
                        UserBlock.blocked_user_id == user_b,
                    ),
                    and_(
                        UserBlock.blocker_user_id == user_b,
                        UserBlock.blocked_user_id == user_a,
                    ),
                )
            )
        )
        return result.scalar_one_or_none() is not None

    async def either_direction_ids(self, viewer_id: uuid.UUID) -> set[uuid.UUID]:
        """Return user IDs that have a block relationship with the viewer in either direction."""
        result = await self._session.execute(
            select(UserBlock.blocker_user_id, UserBlock.blocked_user_id).where(
                or_(
                    UserBlock.blocker_user_id == viewer_id,
                    UserBlock.blocked_user_id == viewer_id,
                )
            )
        )
        ids: set[uuid.UUID] = set()
        for blocker_id, blocked_id in result.all():
            if blocker_id != viewer_id:
                ids.add(blocker_id)
            if blocked_id != viewer_id:
                ids.add(blocked_id)
        return ids

    async def add(
        self,
        *,
        blocker_user_id: uuid.UUID,
        blocked_user_id: uuid.UUID,
        created_at: datetime,
        commit: bool = True,
    ) -> bool:
        """Insert a block. Returns True when a new row was created."""
        statement = (
            insert(UserBlock)
            .values(
                blocker_user_id=blocker_user_id,
                blocked_user_id=blocked_user_id,
                created_at=created_at,
            )
            .on_conflict_do_nothing(
                index_elements=["blocker_user_id", "blocked_user_id"],
            )
            .returning(UserBlock.blocker_user_id)
        )
        result = await self._session.execute(statement)
        inserted = result.scalar_one_or_none() is not None
        if commit:
            await self._session.commit()
        else:
            await self._session.flush()
        return inserted

    async def delete(
        self,
        *,
        blocker_user_id: uuid.UUID,
        blocked_user_id: uuid.UUID,
        commit: bool = True,
    ) -> bool:
        result = await self._session.execute(
            delete(UserBlock).where(
                UserBlock.blocker_user_id == blocker_user_id,
                UserBlock.blocked_user_id == blocked_user_id,
            )
        )
        deleted = int(getattr(result, "rowcount", 0) or 0) > 0
        if commit:
            await self._session.commit()
        else:
            await self._session.flush()
        return deleted

    async def list_blocked_users(self, blocker_user_id: uuid.UUID) -> list[User]:
        result = await self._session.execute(
            select(User)
            .join(UserBlock, UserBlock.blocked_user_id == User.id)
            .where(UserBlock.blocker_user_id == blocker_user_id)
            .order_by(UserBlock.created_at.desc())
        )
        return list(result.scalars().all())
