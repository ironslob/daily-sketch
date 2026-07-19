"""Submission repository."""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import datetime

from sqlalchemy import Select, and_, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.daily_prompt import DailyPrompt
from app.models.sketch_session import SketchSession
from app.models.submission import Submission, SubmissionStatus, SubmissionVisibility
from app.models.upload import Upload
from app.models.user import User, UserStatus

# Authors whose public content remains visible in the community feed/detail.
_PUBLIC_AUTHOR_STATUSES = (UserStatus.incomplete, UserStatus.active)


@dataclass(frozen=True, slots=True)
class FeedRow:
    """One joined feed row loaded without N+1 queries."""

    submission: Submission
    user: User
    prompt: DailyPrompt
    sketch_session: SketchSession
    upload: Upload


class SubmissionRepository:
    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def create(
        self,
        *,
        user_id: uuid.UUID,
        prompt_id: uuid.UUID,
        sketch_session_id: uuid.UUID,
        upload_id: uuid.UUID,
        caption: str | None,
        published_at: datetime,
        commit: bool = True,
    ) -> Submission:
        submission = Submission(
            id=uuid.uuid4(),
            user_id=user_id,
            prompt_id=prompt_id,
            sketch_session_id=sketch_session_id,
            upload_id=upload_id,
            caption=caption,
            visibility=SubmissionVisibility.public,
            status=SubmissionStatus.published,
            like_count=0,
            reflection_count=0,
            published_at=published_at,
        )
        self._session.add(submission)
        if commit:
            await self._session.commit()
            await self._session.refresh(submission)
        else:
            await self._session.flush()
        return submission

    async def get_by_id(self, submission_id: uuid.UUID) -> Submission | None:
        result = await self._session.execute(
            select(Submission).where(Submission.id == submission_id)
        )
        return result.scalar_one_or_none()

    async def get_by_sketch_session_id(
        self,
        sketch_session_id: uuid.UUID,
    ) -> Submission | None:
        result = await self._session.execute(
            select(Submission).where(Submission.sketch_session_id == sketch_session_id)
        )
        return result.scalar_one_or_none()

    async def list_recent_published(
        self,
        *,
        limit: int,
        cursor_published_at: datetime | None = None,
        cursor_id: uuid.UUID | None = None,
        viewer_id: uuid.UUID | None = None,
    ) -> list[FeedRow]:
        """Return up to ``limit`` published feed rows in reverse-chronological order.

        Caller should request ``limit + 1`` to detect a next page.
        ``viewer_id`` is reserved for Phase 11 block filtering.
        """
        statement = self._base_feed_select()

        # Phase 11 will filter authors/targets blocked by or blocking the viewer.
        # The seam is ready; `user_blocks` does not exist yet.
        _ = viewer_id

        if cursor_published_at is not None and cursor_id is not None:
            statement = statement.where(
                or_(
                    Submission.published_at < cursor_published_at,
                    and_(
                        Submission.published_at == cursor_published_at,
                        Submission.id < cursor_id,
                    ),
                )
            )

        statement = statement.order_by(
            Submission.published_at.desc(),
            Submission.id.desc(),
        ).limit(limit)

        result = await self._session.execute(statement)
        rows: list[FeedRow] = []
        for submission, user, prompt, sketch_session, upload in result.all():
            rows.append(
                FeedRow(
                    submission=submission,
                    user=user,
                    prompt=prompt,
                    sketch_session=sketch_session,
                    upload=upload,
                )
            )
        return rows

    def _base_feed_select(
        self,
    ) -> Select[tuple[Submission, User, DailyPrompt, SketchSession, Upload]]:
        return (
            select(Submission, User, DailyPrompt, SketchSession, Upload)
            .join(User, User.id == Submission.user_id)
            .join(DailyPrompt, DailyPrompt.id == Submission.prompt_id)
            .join(SketchSession, SketchSession.id == Submission.sketch_session_id)
            .join(Upload, Upload.id == Submission.upload_id)
            .where(
                Submission.status == SubmissionStatus.published,
                Submission.deleted_at.is_(None),
                Submission.visibility == SubmissionVisibility.public,
                User.status.in_(_PUBLIC_AUTHOR_STATUSES),
                User.deleted_at.is_(None),
            )
        )

    async def soft_delete(self, submission: Submission, *, deleted_at: datetime) -> Submission:
        submission.status = SubmissionStatus.deleted
        submission.deleted_at = deleted_at
        await self._session.commit()
        await self._session.refresh(submission)
        return submission

    async def save(self, submission: Submission) -> Submission:
        await self._session.commit()
        await self._session.refresh(submission)
        return submission
