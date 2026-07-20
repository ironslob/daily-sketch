"""Remove media for soft-deleted submissions after retention."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

from sqlalchemy import select

from app.core.settings import get_settings
from app.db.session import SessionLocal
from app.jobs.runner import job_main
from app.models.submission import Submission, SubmissionStatus
from app.models.upload import Upload
from app.storage.base import get_storage_adapter


async def run(dry_run: bool) -> int:
    settings = get_settings()
    cutoff = datetime.now(UTC) - timedelta(days=settings.cleanup_deleted_media_retention_days)
    storage = get_storage_adapter()
    affected = 0

    async with SessionLocal() as session:
        result = await session.execute(
            select(Submission, Upload)
            .join(Upload, Upload.id == Submission.upload_id)
            .where(
                Submission.status == SubmissionStatus.deleted,
                Submission.deleted_at.is_not(None),
                Submission.deleted_at < cutoff,
                Upload.deleted_at.is_(None),
            )
        )
        rows = result.all()
        for _submission, upload in rows:
            affected += 1
            if dry_run:
                continue
            keys = [
                upload.storage_key,
                storage.derivative_key(original_key=upload.storage_key, kind="display"),
                storage.derivative_key(original_key=upload.storage_key, kind="thumbnail"),
            ]
            for key in keys:
                try:
                    await storage.delete_object(key=key)
                except Exception:
                    pass
            upload.deleted_at = datetime.now(UTC)
        if not dry_run:
            await session.commit()
    return affected


def main() -> None:
    job_main("deleted_media_cleanup", run)


if __name__ == "__main__":
    main()
