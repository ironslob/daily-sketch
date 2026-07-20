"""Shared helpers for scheduled cleanup jobs."""

from __future__ import annotations

import argparse
import asyncio
import logging
from collections.abc import Awaitable, Callable

from app.core.settings import get_settings
from app.observability.metrics import record_job_outcome, send_alert

logger = logging.getLogger(__name__)

JobRunner = Callable[[bool], Awaitable[int]]


async def run_job(name: str, runner: JobRunner, *, dry_run: bool) -> int:
    settings = get_settings()
    try:
        count = await runner(dry_run)
        record_job_outcome(name, success=True)
        logger.info("job_completed job=%s dry_run=%s count=%s", name, dry_run, count)
        return count
    except Exception:
        record_job_outcome(name, success=False)
        logger.exception("job_failed job=%s dry_run=%s", name, dry_run)
        await send_alert(settings, title=f"Job failed: {name}", detail=f"dry_run={dry_run}")
        raise


def job_main(name: str, runner: JobRunner) -> None:
    parser = argparse.ArgumentParser(description=f"Run {name} cleanup job")
    parser.add_argument(
        "--dry-run", action="store_true", help="Report actions without mutating data"
    )
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO)

    async def _run() -> None:
        count = await run_job(name, runner, dry_run=args.dry_run)
        print(f"{name}: {'would affect' if args.dry_run else 'affected'} {count} row(s).")

    asyncio.run(_run())
