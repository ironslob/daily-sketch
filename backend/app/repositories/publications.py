"""Creative publication repository."""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import date, datetime
from typing import Any

from sqlalchemy import Select, and_, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.creative_publication import (
    CreativePublication,
    PublicationStatus,
    PublicationVisibility,
)
from app.models.daily_prompt import DailyPrompt
from app.models.enums import CreativeType
from app.models.sketch_session import SketchSession
from app.models.sketch_submission import SketchSubmission
from app.models.story_session import StorySession
from app.models.story_submission import StorySubmission
from app.models.upload import Upload
from app.models.user import User, UserStatus

_PUBLIC_AUTHOR_STATUSES = (UserStatus.incomplete, UserStatus.active)


@dataclass(frozen=True, slots=True)
class FeedRow:
    """One joined feed row loaded without N+1 queries."""

    publication: CreativePublication
    user: User
    prompt: DailyPrompt
    sketch_session: SketchSession | None
    story_session: StorySession | None
    sketch_submission: SketchSubmission | None
    story_submission: StorySubmission | None
    upload: Upload | None


class PublicationRepository:
    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def create_sketch(
        self,
        *,
        user_id: uuid.UUID,
        prompt_id: uuid.UUID,
        session_id: uuid.UUID,
        sketch_session_id: uuid.UUID,
        upload_id: uuid.UUID,
        caption: str | None,
        published_at: datetime,
        commit: bool = True,
    ) -> tuple[CreativePublication, SketchSubmission]:
        publication = CreativePublication(
            id=uuid.uuid4(),
            user_id=user_id,
            prompt_id=prompt_id,
            creative_type=CreativeType.sketch,
            session_id=session_id,
            visibility=PublicationVisibility.public,
            status=PublicationStatus.published,
            like_count=0,
            reflection_count=0,
            published_at=published_at,
        )
        detail = SketchSubmission(
            publication_id=publication.id,
            sketch_session_id=sketch_session_id,
            upload_id=upload_id,
            caption=caption,
        )
        self._session.add(publication)
        self._session.add(detail)
        if commit:
            await self._session.commit()
            await self._session.refresh(publication)
            await self._session.refresh(detail)
        else:
            await self._session.flush()
        return publication, detail

    async def create_story(
        self,
        *,
        user_id: uuid.UUID,
        prompt_id: uuid.UUID,
        session_id: uuid.UUID,
        story_session_id: uuid.UUID,
        body: str,
        caption: str | None,
        published_at: datetime,
        commit: bool = True,
    ) -> tuple[CreativePublication, StorySubmission]:
        publication = CreativePublication(
            id=uuid.uuid4(),
            user_id=user_id,
            prompt_id=prompt_id,
            creative_type=CreativeType.story,
            session_id=session_id,
            visibility=PublicationVisibility.public,
            status=PublicationStatus.published,
            like_count=0,
            reflection_count=0,
            published_at=published_at,
        )
        detail = StorySubmission(
            publication_id=publication.id,
            story_session_id=story_session_id,
            body=body,
            caption=caption,
        )
        self._session.add(publication)
        self._session.add(detail)
        if commit:
            await self._session.commit()
            await self._session.refresh(publication)
            await self._session.refresh(detail)
        else:
            await self._session.flush()
        return publication, detail

    async def get_by_id(self, publication_id: uuid.UUID) -> CreativePublication | None:
        result = await self._session.execute(
            select(CreativePublication).where(CreativePublication.id == publication_id)
        )
        return result.scalar_one_or_none()

    async def get_sketch_submission_by_session_id(
        self,
        sketch_session_id: uuid.UUID,
    ) -> SketchSubmission | None:
        result = await self._session.execute(
            select(SketchSubmission).where(SketchSubmission.sketch_session_id == sketch_session_id)
        )
        return result.scalar_one_or_none()

    async def get_story_submission_by_session_id(
        self,
        story_session_id: uuid.UUID,
    ) -> StorySubmission | None:
        result = await self._session.execute(
            select(StorySubmission).where(StorySubmission.story_session_id == story_session_id)
        )
        return result.scalar_one_or_none()

    async def get_sketch_submission(
        self,
        publication_id: uuid.UUID,
    ) -> SketchSubmission | None:
        return await self._session.get(SketchSubmission, publication_id)

    async def get_story_submission(
        self,
        publication_id: uuid.UUID,
    ) -> StorySubmission | None:
        return await self._session.get(StorySubmission, publication_id)

    async def list_recent_published(
        self,
        *,
        limit: int,
        cursor_published_at: datetime | None = None,
        cursor_id: uuid.UUID | None = None,
        viewer_id: uuid.UUID | None = None,
        excluded_author_ids: set[uuid.UUID] | None = None,
        creative_type: CreativeType,
    ) -> list[FeedRow]:
        statement = self._base_feed_select().where(
            CreativePublication.creative_type == creative_type
        )

        if excluded_author_ids:
            statement = statement.where(CreativePublication.user_id.notin_(excluded_author_ids))
        else:
            _ = viewer_id

        if cursor_published_at is not None and cursor_id is not None:
            statement = statement.where(
                or_(
                    CreativePublication.published_at < cursor_published_at,
                    and_(
                        CreativePublication.published_at == cursor_published_at,
                        CreativePublication.id < cursor_id,
                    ),
                )
            )

        statement = statement.order_by(
            CreativePublication.published_at.desc(),
            CreativePublication.id.desc(),
        ).limit(limit)

        return await self._map_feed_rows(statement)

    async def list_user_published(
        self,
        *,
        user_id: uuid.UUID,
        limit: int,
        cursor_published_at: datetime | None = None,
        cursor_id: uuid.UUID | None = None,
        viewer_id: uuid.UUID | None = None,
        excluded_author_ids: set[uuid.UUID] | None = None,
        creative_type: CreativeType,
    ) -> list[FeedRow]:
        statement = self._base_feed_select().where(
            CreativePublication.user_id == user_id,
            CreativePublication.creative_type == creative_type,
        )

        if excluded_author_ids and user_id in excluded_author_ids:
            return []
        _ = viewer_id

        if cursor_published_at is not None and cursor_id is not None:
            statement = statement.where(
                or_(
                    CreativePublication.published_at < cursor_published_at,
                    and_(
                        CreativePublication.published_at == cursor_published_at,
                        CreativePublication.id < cursor_id,
                    ),
                )
            )

        statement = statement.order_by(
            CreativePublication.published_at.desc(),
            CreativePublication.id.desc(),
        ).limit(limit)

        return await self._map_feed_rows(statement)

    async def count_user_published(
        self,
        user_id: uuid.UUID,
        *,
        creative_type: CreativeType,
    ) -> int:
        stmt = (
            select(func.count())
            .select_from(CreativePublication)
            .where(
                CreativePublication.user_id == user_id,
                CreativePublication.status == PublicationStatus.published,
                CreativePublication.deleted_at.is_(None),
                CreativePublication.visibility == PublicationVisibility.public,
                CreativePublication.creative_type == creative_type,
            )
        )
        result = await self._session.execute(stmt)
        return int(result.scalar_one())

    async def published_prompt_dates(
        self,
        user_id: uuid.UUID,
        *,
        creative_type: CreativeType,
    ) -> list[date]:
        stmt = (
            select(DailyPrompt.prompt_date)
            .join(CreativePublication, CreativePublication.prompt_id == DailyPrompt.id)
            .where(
                CreativePublication.user_id == user_id,
                CreativePublication.status == PublicationStatus.published,
                CreativePublication.deleted_at.is_(None),
                CreativePublication.visibility == PublicationVisibility.public,
                CreativePublication.creative_type == creative_type,
            )
            .distinct()
            .order_by(DailyPrompt.prompt_date.desc())
        )
        result = await self._session.execute(stmt)
        return list(result.scalars().all())

    async def _map_feed_rows(self, statement: Select[Any]) -> list[FeedRow]:
        result = await self._session.execute(statement)
        rows: list[FeedRow] = []
        for (
            publication,
            user,
            prompt,
            sketch_session,
            story_session,
            sketch_submission,
            story_submission,
            upload,
        ) in result.all():
            rows.append(
                FeedRow(
                    publication=publication,
                    user=user,
                    prompt=prompt,
                    sketch_session=sketch_session,
                    story_session=story_session,
                    sketch_submission=sketch_submission,
                    story_submission=story_submission,
                    upload=upload,
                )
            )
        return rows

    def _base_feed_select(
        self,
    ) -> Select[Any]:
        return (
            select(
                CreativePublication,
                User,
                DailyPrompt,
                SketchSession,
                StorySession,
                SketchSubmission,
                StorySubmission,
                Upload,
            )
            .join(User, User.id == CreativePublication.user_id)
            .join(DailyPrompt, DailyPrompt.id == CreativePublication.prompt_id)
            .outerjoin(
                SketchSubmission,
                SketchSubmission.publication_id == CreativePublication.id,
            )
            .outerjoin(
                StorySubmission,
                StorySubmission.publication_id == CreativePublication.id,
            )
            .outerjoin(
                SketchSession,
                SketchSession.id == CreativePublication.session_id,
            )
            .outerjoin(
                StorySession,
                StorySession.id == CreativePublication.session_id,
            )
            .outerjoin(Upload, Upload.id == SketchSubmission.upload_id)
            .where(
                CreativePublication.status == PublicationStatus.published,
                CreativePublication.deleted_at.is_(None),
                CreativePublication.visibility == PublicationVisibility.public,
                User.status.in_(_PUBLIC_AUTHOR_STATUSES),
                User.deleted_at.is_(None),
            )
        )

    async def soft_delete(
        self,
        publication: CreativePublication,
        *,
        deleted_at: datetime,
    ) -> CreativePublication:
        publication.status = PublicationStatus.deleted
        publication.deleted_at = deleted_at
        await self._session.commit()
        await self._session.refresh(publication)
        return publication

    async def list_all_for_user(self, user_id: uuid.UUID) -> list[CreativePublication]:
        result = await self._session.execute(
            select(CreativePublication).where(CreativePublication.user_id == user_id)
        )
        return list(result.scalars().all())

    async def list_published_for_user_ids(
        self,
        user_id: uuid.UUID,
    ) -> list[CreativePublication]:
        result = await self._session.execute(
            select(CreativePublication).where(
                CreativePublication.user_id == user_id,
                CreativePublication.status == PublicationStatus.published,
                CreativePublication.deleted_at.is_(None),
            )
        )
        return list(result.scalars().all())

    async def set_status(
        self,
        publication: CreativePublication,
        *,
        status: PublicationStatus,
        deleted_at: datetime | None = None,
        commit: bool = True,
    ) -> CreativePublication:
        publication.status = status
        if deleted_at is not None:
            publication.deleted_at = deleted_at
        elif status == PublicationStatus.published:
            publication.deleted_at = None
        if commit:
            await self._session.commit()
            await self._session.refresh(publication)
        else:
            await self._session.flush()
        return publication

    async def save(self, publication: CreativePublication) -> CreativePublication:
        await self._session.commit()
        await self._session.refresh(publication)
        return publication


# Backward-compatible alias.
SubmissionRepository = PublicationRepository
