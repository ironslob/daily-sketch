"""Finalize pending account deletions.

Usage:
    python -m app.jobs.account_deletion
    python -m app.jobs.account_deletion --dry-run
"""

from __future__ import annotations

from app.core.clock import SystemClock
from app.core.settings import get_settings
from app.db.session import SessionLocal
from app.jobs.runner import job_main
from app.services.account_deletion import AccountDeletionService
from app.storage.base import get_storage_adapter


async def run(dry_run: bool) -> int:
    settings = get_settings()
    storage = get_storage_adapter()
    async with SessionLocal() as session:
        service = AccountDeletionService(
            session,
            SystemClock(),
            settings=settings,
            storage=storage,
        )
        return await service.finalize_pending(dry_run=dry_run)


def main() -> None:
    job_main("account_deletion_finalize", run)


if __name__ == "__main__":
    main()
