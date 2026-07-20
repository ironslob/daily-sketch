"""Development seed helpers for Phase 11 safety fixtures.

Usage (after prompt seed and with a running DB):
  python -m app.seeds.safety
"""

from __future__ import annotations

import asyncio
import uuid
from datetime import UTC, datetime

from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

from app.core.settings import get_settings
from app.models.report import ReportReason, ReportTargetType
from app.models.user import User, UserStatus
from app.repositories.blocks import BlockRepository
from app.repositories.reports import ReportRepository
from app.repositories.users import UserRepository


async def seed_safety() -> None:
    settings = get_settings()
    engine = create_async_engine(settings.database_url, pool_pre_ping=True)
    session_factory = async_sessionmaker(engine, expire_on_commit=False)
    now = datetime.now(UTC)
    async with session_factory() as session:
        users = UserRepository(session)
        blocks = BlockRepository(session)
        reports = ReportRepository(session)

        blocker = await users.get_by_username_normalized("safety_blocker")
        if blocker is None:
            blocker = User(
                id=uuid.uuid4(),
                descope_subject=f"seed-blocker-{uuid.uuid4()}",
                username="safety_blocker",
                username_normalized="safety_blocker",
                display_name="Safety Blocker",
                status=UserStatus.active,
                profile_completed_at=now,
            )
            session.add(blocker)
            await session.flush()

        blocked = await users.get_by_username_normalized("safety_blocked")
        if blocked is None:
            blocked = User(
                id=uuid.uuid4(),
                descope_subject=f"seed-blocked-{uuid.uuid4()}",
                username="safety_blocked",
                username_normalized="safety_blocked",
                display_name="Safety Blocked",
                status=UserStatus.active,
                profile_completed_at=now,
            )
            session.add(blocked)
            await session.flush()

        await blocks.add(
            blocker_user_id=blocker.id,
            blocked_user_id=blocked.id,
            created_at=now,
            commit=False,
        )
        existing = await reports.find_open(
            reporter_user_id=blocker.id,
            target_type=ReportTargetType.profile,
            target_id=blocked.id,
        )
        if existing is None:
            await reports.create(
                reporter_user_id=blocker.id,
                target_type=ReportTargetType.profile,
                target_id=blocked.id,
                reason=ReportReason.spam,
                notes="Seed open report",
                commit=False,
            )
        await session.commit()
        print(f"Seeded block {blocker.username} → {blocked.username} and an open profile report.")
    await engine.dispose()


def main() -> None:
    asyncio.run(seed_safety())


if __name__ == "__main__":
    main()
