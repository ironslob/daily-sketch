"""Finalize pending account deletions.

Usage:
    python -m app.jobs.account_deletion
"""

from __future__ import annotations

import asyncio
import logging

from app.core.clock import SystemClock
from app.core.settings import get_settings
from app.db.session import SessionLocal
from app.services.account_deletion import AccountDeletionService
from app.storage.base import get_storage_adapter

logger = logging.getLogger(__name__)


async def run() -> int:
    settings = get_settings()
    storage = get_storage_adapter()
    async with SessionLocal() as session:
        service = AccountDeletionService(
            session,
            SystemClock(),
            settings=settings,
            storage=storage,
        )
        count = await service.finalize_pending()
        logger.info("account_deletion_finalize count=%s", count)
        return count


def main() -> None:
    logging.basicConfig(level=logging.INFO)
    count = asyncio.run(run())
    print(f"Finalized {count} pending deletion account(s).")


if __name__ == "__main__":
    main()
