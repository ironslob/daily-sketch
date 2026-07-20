"""Blocking application service."""

from __future__ import annotations

import uuid
from datetime import timedelta

from sqlalchemy.ext.asyncio import AsyncSession

from app.core.clock import Clock
from app.core.errors import AppError
from app.core.settings import Settings, get_settings
from app.models.user import User
from app.repositories.blocks import BlockRepository
from app.repositories.uploads import UploadRepository
from app.repositories.users import UserRepository
from app.schemas.safety import BlockedUserSummary, BlockedUsersResponse, BlockState
from app.services.media_urls import resolve_avatar_url, resolve_avatar_urls
from app.storage.base import StorageAdapter


class BlockService:
    def __init__(
        self,
        session: AsyncSession,
        clock: Clock,
        settings: Settings | None = None,
        storage: StorageAdapter | None = None,
    ) -> None:
        self._session = session
        self._blocks = BlockRepository(session)
        self._users = UserRepository(session)
        self._uploads = UploadRepository(session)
        self._clock = clock
        self._settings = settings or get_settings()
        self._storage = storage

    async def block(self, *, blocker: User, user_id: uuid.UUID) -> BlockState:
        if blocker.id == user_id:
            raise AppError(
                code="cannot_block_self",
                message="You cannot block yourself.",
                status_code=422,
            )
        target = await self._users.get_by_id(user_id)
        if target is None:
            raise AppError(
                code="user_not_found",
                message="The requested user could not be found.",
                status_code=404,
            )
        await self._blocks.add(
            blocker_user_id=blocker.id,
            blocked_user_id=user_id,
            created_at=self._clock.now(),
        )
        return BlockState(blocked=True, user_id=user_id)

    async def unblock(self, *, blocker: User, user_id: uuid.UUID) -> BlockState:
        target = await self._users.get_by_id(user_id)
        if target is None:
            raise AppError(
                code="user_not_found",
                message="The requested user could not be found.",
                status_code=404,
            )
        await self._blocks.delete(blocker_user_id=blocker.id, blocked_user_id=user_id)
        return BlockState(blocked=False, user_id=user_id)

    async def list_blocked_users(self, *, blocker: User) -> BlockedUsersResponse:
        users = await self._blocks.list_blocked_users(blocker.id)
        expires_at = self._clock.now() + timedelta(
            seconds=self._settings.signed_read_expiry_seconds
        )
        avatar_urls: dict[uuid.UUID, str | None] = {}
        if self._storage is not None and users:
            avatar_upload_ids = [user.avatar_upload_id for user in users]
            uploads_by_id = await self._uploads.get_by_ids(
                [upload_id for upload_id in avatar_upload_ids if upload_id is not None]
            )
            avatar_urls = await resolve_avatar_urls(
                storage=self._storage,
                uploads_by_id=uploads_by_id,
                avatar_upload_ids=avatar_upload_ids,
                expires_at=expires_at,
            )

        items: list[BlockedUserSummary] = []
        for user in users:
            avatar_url = None
            if user.avatar_upload_id is not None:
                avatar_url = avatar_urls.get(user.avatar_upload_id)
                if avatar_url is None and self._storage is not None:
                    upload = await self._uploads.get_by_id(user.avatar_upload_id)
                    avatar_url = await resolve_avatar_url(
                        storage=self._storage,
                        upload=upload,
                        expires_at=expires_at,
                    )
            items.append(
                BlockedUserSummary(
                    user_id=user.id,
                    username=user.username or "",
                    display_name=user.display_name,
                    avatar_url=avatar_url,
                )
            )
        return BlockedUsersResponse(items=items)

    async def exclude_ids_for(self, viewer_id: uuid.UUID | None) -> set[uuid.UUID]:
        if viewer_id is None:
            return set()
        return await self._blocks.either_direction_ids(viewer_id)

    async def is_blocked_either_way(self, *, viewer_id: uuid.UUID, other_id: uuid.UUID) -> bool:
        return await self._blocks.either_direction_exists(user_a=viewer_id, user_b=other_id)
