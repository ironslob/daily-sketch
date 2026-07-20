"""Detect missing tomorrow Daily Prompt and exit non-zero for schedulers."""

from __future__ import annotations

from datetime import timedelta

from app.core.clock import SystemClock
from app.db.session import SessionLocal
from app.jobs.runner import job_main
from app.repositories.prompts import PromptRepository


async def run(dry_run: bool) -> int:
    clock = SystemClock()
    tomorrow = clock.today() + timedelta(days=1)
    async with SessionLocal() as session:
        repo = PromptRepository(session)
        prompt = await repo.get_published_by_date(tomorrow)
        if prompt is None:
            if not dry_run:
                raise RuntimeError(f"Missing published prompt for {tomorrow.isoformat()}")
            return 0
        return 1


def main() -> None:
    job_main("missing_prompt_check", run)


if __name__ == "__main__":
    main()
