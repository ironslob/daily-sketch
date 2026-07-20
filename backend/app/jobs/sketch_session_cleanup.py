"""Expire stale active sketch sessions."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

from sqlalchemy import select, update

from app.core.settings import get_settings
from app.db.session import SessionLocal
from app.jobs.runner import job_main
from app.models.sketch_session import SketchSession, SketchSessionStatus


async def run(dry_run: bool) -> int:
    settings = get_settings()
    cutoff = datetime.now(UTC) - timedelta(seconds=settings.sketch_session_expiry_seconds)

    async with SessionLocal() as session:
        result = await session.execute(
            select(SketchSession.id).where(
                SketchSession.status.in_(
                    [
                        SketchSessionStatus.active,
                        SketchSessionStatus.paused,
                        SketchSessionStatus.ready_for_photo,
                        SketchSessionStatus.uploading,
                    ]
                ),
                SketchSession.started_at < cutoff,
            )
        )
        ids = [row[0] for row in result.all()]
        if dry_run or not ids:
            return len(ids)
        await session.execute(
            update(SketchSession)
            .where(SketchSession.id.in_(ids))
            .values(status=SketchSessionStatus.expired, abandoned_at=datetime.now(UTC))
        )
        await session.commit()
        return len(ids)


def main() -> None:
    job_main("sketch_session_cleanup", run)


if __name__ == "__main__":
    main()
