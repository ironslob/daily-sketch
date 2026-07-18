"""Deterministic Daily Prompt generation and seed commands.

Usage:
  python -m app.seeds.prompts            # seed today + 30 future days
  python -m app.seeds.prompts --days 7   # seed today + 7 future days
  python -m app.seeds.prompts --date 2026-07-18  # seed a single Prompt Date
"""

from __future__ import annotations

import argparse
import asyncio
import hashlib
import random
from datetime import UTC, date, datetime, timedelta
from pathlib import Path

from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.core.settings import get_settings
from app.repositories.prompts import PromptRepository

WORD_LIST_PATH = Path(__file__).resolve().parent.parent / "data" / "prompt_words.txt"


def load_word_list(path: Path = WORD_LIST_PATH) -> list[str]:
    """Load curated non-empty prompt words."""
    if not path.is_file():
        raise FileNotFoundError(f"Prompt word list not found: {path}")
    words = [line.strip() for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]
    if len(words) < 3:
        raise ValueError("Prompt word list must contain at least three words.")
    return words


def validate_prompt_words(words: tuple[str, str, str]) -> tuple[str, str, str]:
    """Validate three non-empty distinct words in display order."""
    cleaned = tuple(word.strip() for word in words)
    if len(cleaned) != 3:
        raise ValueError("A Daily Prompt must contain exactly three words.")
    if any(not word for word in cleaned):
        raise ValueError("Prompt words must be non-empty.")
    if len(set(word.casefold() for word in cleaned)) != 3:
        raise ValueError("Prompt words must be unique within a Daily Prompt.")
    word_1, word_2, word_3 = cleaned
    return (word_1, word_2, word_3)


def generate_prompt_words(
    prompt_date: date, words: list[str] | None = None
) -> tuple[str, str, str]:
    """Deterministically select three distinct words for a Prompt Date."""
    catalog = words if words is not None else load_word_list()
    if len(catalog) < 3:
        raise ValueError("Word catalog must contain at least three words.")

    seed_material = f"daily-sketch:{prompt_date.isoformat()}".encode()
    seed_int = int.from_bytes(hashlib.sha256(seed_material).digest()[:8], "big")
    rng = random.Random(seed_int)
    selected = rng.sample(catalog, 3)
    return validate_prompt_words((selected[0], selected[1], selected[2]))


async def seed_prompts(
    *,
    session: AsyncSession,
    start_date: date,
    days: int,
    published_at: datetime | None = None,
) -> list[date]:
    """Upsert published prompts for ``start_date`` through ``start_date + days`` inclusive of start."""
    if days < 0:
        raise ValueError("days must be >= 0")

    repo = PromptRepository(session)
    catalog = load_word_list()
    published = published_at or datetime.now(UTC)
    seeded: list[date] = []

    for offset in range(days + 1):
        prompt_date = start_date + timedelta(days=offset)
        word_1, word_2, word_3 = generate_prompt_words(prompt_date, catalog)
        await repo.upsert_published(
            prompt_date=prompt_date,
            word_1=word_1,
            word_2=word_2,
            word_3=word_3,
            published_at=published,
        )
        seeded.append(prompt_date)

    return seeded


async def _run(start_date: date, days: int) -> None:
    settings = get_settings()
    engine = create_async_engine(settings.database_url, pool_pre_ping=True)
    session_factory = async_sessionmaker(engine, expire_on_commit=False)
    try:
        async with session_factory() as session:
            seeded = await seed_prompts(session=session, start_date=start_date, days=days)
        print(f"Seeded {len(seeded)} Daily Prompt(s) from {seeded[0]} to {seeded[-1]}.")
    finally:
        await engine.dispose()


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description="Seed Daily Prompts deterministically.")
    parser.add_argument(
        "--date",
        type=date.fromisoformat,
        default=None,
        help="UTC Prompt Date to start from (default: today UTC).",
    )
    parser.add_argument(
        "--days",
        type=int,
        default=30,
        help="Number of additional future days to seed after the start date (default: 30).",
    )
    args = parser.parse_args(argv)
    start = args.date or datetime.now(UTC).date()
    asyncio.run(_run(start, args.days))


if __name__ == "__main__":
    main()
