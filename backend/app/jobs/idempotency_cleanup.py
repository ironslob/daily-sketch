"""Remove expired idempotency records."""

from __future__ import annotations

from datetime import UTC, datetime

from sqlalchemy import delete

from app.db.session import SessionLocal
from app.jobs.runner import job_main
from app.models.idempotency_key import IdempotencyKey


async def run(dry_run: bool) -> int:
    now = datetime.now(UTC)
    async with SessionLocal() as session:
        if dry_run:
            from sqlalchemy import func, select

            result = await session.execute(
                select(func.count())
                .select_from(IdempotencyKey)
                .where(IdempotencyKey.expires_at < now)
            )
            return int(result.scalar_one())
        result = await session.execute(
            delete(IdempotencyKey)
            .where(IdempotencyKey.expires_at < now)
            .returning(IdempotencyKey.id)
        )
        deleted = result.all()
        await session.commit()
        return len(deleted)


def main() -> None:
    job_main("idempotency_cleanup", run)


if __name__ == "__main__":
    main()
