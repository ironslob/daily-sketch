"""Ensure today and tomorrow Daily Prompts exist; alert if ensure fails."""

from __future__ import annotations

from datetime import timedelta

from app.core.clock import SystemClock
from app.core.errors import AppError
from app.db.session import SessionLocal
from app.jobs.runner import job_main
from app.repositories.prompts import PromptRepository
from app.services.prompts import PromptService


async def run(dry_run: bool) -> int:
    clock = SystemClock()
    today = clock.today()
    dates = (today, today + timedelta(days=1))
    async with SessionLocal() as session:
        if dry_run:
            repo = PromptRepository(session)
            present = 0
            for prompt_date in dates:
                if await repo.get_published_by_date(prompt_date) is not None:
                    present += 1
            return present

        service = PromptService(session, clock)
        for prompt_date in dates:
            try:
                await service.ensure_published(prompt_date)
            except AppError as exc:
                raise RuntimeError(
                    f"Could not ensure published prompt for {prompt_date.isoformat()}: {exc.code}"
                ) from exc

        repo = PromptRepository(session)
        for prompt_date in dates:
            if await repo.get_published_by_date(prompt_date) is None:
                raise RuntimeError(f"Missing published prompt for {prompt_date.isoformat()}")
        return len(dates)


def main() -> None:
    job_main("missing_prompt_check", run)


if __name__ == "__main__":
    main()
