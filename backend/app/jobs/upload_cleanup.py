"""Expire stale pending uploads and remove orphaned objects."""

from __future__ import annotations

from datetime import UTC, datetime

from sqlalchemy import and_, select

from app.db.session import SessionLocal
from app.jobs.runner import job_main
from app.models.upload import Upload, UploadStatus
from app.storage.base import get_storage_adapter


async def run(dry_run: bool) -> int:
    now = datetime.now(UTC)
    storage = get_storage_adapter()
    affected = 0

    async with SessionLocal() as session:
        result = await session.execute(
            select(Upload).where(
                and_(
                    Upload.deleted_at.is_(None),
                    Upload.status.in_([UploadStatus.pending, UploadStatus.failed]),
                    Upload.expires_at < now,
                )
            )
        )
        uploads = list(result.scalars().all())
        for upload in uploads:
            affected += 1
            if dry_run:
                continue
            upload.status = UploadStatus.expired
            try:
                await storage.delete_object(key=upload.storage_key)
                for kind in ("display", "thumbnail"):
                    await storage.delete_object(
                        key=storage.derivative_key(original_key=upload.storage_key, kind=kind)
                    )
            except Exception:
                pass
        if not dry_run:
            await session.commit()
    return affected


def main() -> None:
    job_main("upload_cleanup", run)


if __name__ == "__main__":
    main()
