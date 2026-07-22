"""Shared creative session service base class."""

from __future__ import annotations

import hashlib
import json
import uuid
from abc import ABC, abstractmethod
from datetime import timedelta
from enum import Enum
from typing import Any, Generic, TypeVar

from sqlalchemy.ext.asyncio import AsyncSession

from app.core.clock import Clock
from app.core.errors import AppError
from app.core.settings import Settings, get_settings
from app.models.enums import TimerMode
from app.models.user import User
from app.repositories.idempotency import IdempotencyRepository
from app.repositories.prompts import PromptRepository
from app.services.preferences import ALLOWED_TIMER_SECONDS

CreateRequestT = TypeVar("CreateRequestT")
EventRequestT = TypeVar("EventRequestT")
ResponseT = TypeVar("ResponseT")
SessionT = TypeVar("SessionT")
EventTypeT = TypeVar("EventTypeT")
StatusT = TypeVar("StatusT", bound=Enum)


class BaseCreativeSessionService(
    ABC, Generic[SessionT, EventTypeT, StatusT, CreateRequestT, EventRequestT, ResponseT]
):
    """Shared session lifecycle logic for all creative types."""

    create_endpoint: str
    client_events: frozenset[EventTypeT]
    terminal_statuses: frozenset[StatusT]

    def __init__(
        self,
        session: AsyncSession,
        clock: Clock,
        settings: Settings | None = None,
    ) -> None:
        self._session = session
        self._prompts = PromptRepository(session)
        self._idempotency = IdempotencyRepository(session)
        self._clock = clock
        self._settings = settings or get_settings()

    async def create(
        self,
        *,
        user: User,
        payload: CreateRequestT,
        idempotency_key: str | None,
    ) -> tuple[ResponseT, int]:
        request_hash = self._hash_create_request(payload)
        if idempotency_key:
            existing = await self._idempotency.get(
                user_id=user.id,
                endpoint=self.create_endpoint,
                key=idempotency_key,
            )
            if existing is not None:
                if existing.request_hash != request_hash:
                    raise AppError(
                        code="idempotency_key_conflict",
                        message="This idempotency key was already used with a different request.",
                        status_code=409,
                    )
                return self._deserialize_response(existing.response_body), existing.response_status

        prompt = await self._prompts.get_published_by_id(self._prompt_id(payload))
        if prompt is None:
            raise AppError(
                code="prompt_not_found",
                message="The requested prompt could not be found.",
                status_code=404,
            )

        timer_mode = TimerMode(self._timer_mode_value(payload))
        validate_timer_selection(timer_mode, self._selected_timer_seconds(payload))

        now = self._clock.now()
        metadata: dict[str, Any] = {}
        client_timezone = self._client_timezone(payload)
        client_session_id = self._client_session_id(payload)
        if client_timezone:
            metadata["client_timezone"] = client_timezone
        if client_session_id:
            metadata["client_session_id"] = client_session_id

        creative_session = await self._create_session(
            user_id=user.id,
            prompt_id=prompt.id,
            timer_mode=timer_mode,
            selected_timer_seconds=self._selected_timer_seconds(payload),
            started_at=now,
            started_metadata=metadata or None,
        )
        response = self._to_response(creative_session)

        if idempotency_key:
            await self._idempotency.put(
                user_id=user.id,
                endpoint=self.create_endpoint,
                key=idempotency_key,
                request_hash=request_hash,
                response_status=201,
                response_body=self._serialize_response(response),
                expires_at=now + timedelta(days=7),
            )

        return response, 201

    async def get(self, *, user: User, session_id: uuid.UUID) -> ResponseT:
        creative_session = await self._require_owned_session(user=user, session_id=session_id)
        creative_session = await self._maybe_expire(creative_session)
        return self._to_response(creative_session)

    async def record_event(
        self,
        *,
        user: User,
        session_id: uuid.UUID,
        payload: EventRequestT,
    ) -> ResponseT:
        creative_session = await self._require_owned_session(user=user, session_id=session_id)
        creative_session = await self._maybe_expire(creative_session)

        event_type = self._parse_event_type(payload)
        if event_type not in self.client_events:
            raise AppError(
                code="invalid_session_transition",
                message="That lifecycle event is not valid for the current session state.",
                status_code=422,
                details={
                    "event_type": self._event_type_value(event_type),
                    "status": self._status_value(creative_session),
                },
            )

        if self._is_abandon_event(event_type):
            return await self.abandon(user=user, session_id=session_id)

        self._assert_transition_allowed(creative_session, event_type)

        now = self._clock.now()
        await self._add_event(
            creative_session=creative_session,
            event_type=event_type,
            occurred_at=now,
            client_occurred_at=self._client_occurred_at(payload),
            metadata=self._event_metadata(payload),
        )
        await self._apply_event_side_effects(creative_session, event_type, now)
        creative_session = await self._save_session(creative_session)
        return self._to_response(creative_session)

    async def abandon(self, *, user: User, session_id: uuid.UUID) -> ResponseT:
        creative_session = await self._require_owned_session(user=user, session_id=session_id)
        if self._is_abandoned(creative_session):
            return self._to_response(creative_session)

        if self._is_abandon_forbidden(creative_session):
            raise AppError(
                code="invalid_session_transition",
                message="That lifecycle event is not valid for the current session state.",
                status_code=422,
                details={
                    "event_type": self._abandon_event_value(),
                    "status": self._status_value(creative_session),
                },
            )

        now = self._clock.now()
        await self._add_event(
            creative_session=creative_session,
            event_type=self._abandon_event_type(),
            occurred_at=now,
        )
        self._mark_abandoned(creative_session, now)
        creative_session = await self._save_session(creative_session)
        return self._to_response(creative_session)

    async def _maybe_expire(self, creative_session: SessionT) -> SessionT:
        if self._status_value(creative_session) in {
            status.value for status in self.terminal_statuses
        }:
            return creative_session
        expiry_seconds = self._settings.creative_session_expiry_seconds
        age = self._clock.now() - self._started_at(creative_session)
        if age.total_seconds() < expiry_seconds:
            return creative_session
        self._mark_expired(creative_session)
        return await self._save_session(creative_session)

    @abstractmethod
    def _hash_create_request(self, payload: CreateRequestT) -> str: ...

    @abstractmethod
    def _prompt_id(self, payload: CreateRequestT) -> uuid.UUID: ...

    @abstractmethod
    def _timer_mode_value(self, payload: CreateRequestT) -> str: ...

    @abstractmethod
    def _selected_timer_seconds(self, payload: CreateRequestT) -> int | None: ...

    @abstractmethod
    def _client_timezone(self, payload: CreateRequestT) -> str | None: ...

    @abstractmethod
    def _client_session_id(self, payload: CreateRequestT) -> str | None: ...

    @abstractmethod
    async def _create_session(
        self,
        *,
        user_id: uuid.UUID,
        prompt_id: uuid.UUID,
        timer_mode: TimerMode,
        selected_timer_seconds: int | None,
        started_at: Any,
        started_metadata: dict[str, Any] | None,
    ) -> SessionT: ...

    @abstractmethod
    def _to_response(self, creative_session: SessionT) -> ResponseT: ...

    @abstractmethod
    def _serialize_response(self, response: ResponseT) -> dict[str, Any]: ...

    @abstractmethod
    def _deserialize_response(self, body: dict[str, Any]) -> ResponseT: ...

    @abstractmethod
    async def _require_owned_session(self, *, user: User, session_id: uuid.UUID) -> SessionT: ...

    @abstractmethod
    def _parse_event_type(self, payload: EventRequestT) -> EventTypeT: ...

    @abstractmethod
    def _event_type_value(self, event_type: EventTypeT) -> str: ...

    @abstractmethod
    def _status_value(self, creative_session: SessionT) -> str: ...

    @abstractmethod
    def _is_abandon_event(self, event_type: EventTypeT) -> bool: ...

    @abstractmethod
    def _assert_transition_allowed(
        self,
        creative_session: SessionT,
        event_type: EventTypeT,
    ) -> None: ...

    @abstractmethod
    async def _add_event(
        self,
        *,
        creative_session: SessionT,
        event_type: EventTypeT,
        occurred_at: Any,
        client_occurred_at: Any | None = None,
        metadata: dict[str, Any] | None = None,
    ) -> None: ...

    @abstractmethod
    async def _apply_event_side_effects(
        self,
        creative_session: SessionT,
        event_type: EventTypeT,
        now: Any,
    ) -> None: ...

    @abstractmethod
    async def _save_session(self, creative_session: SessionT) -> SessionT: ...

    @abstractmethod
    def _is_abandoned(self, creative_session: SessionT) -> bool: ...

    @abstractmethod
    def _is_abandon_forbidden(self, creative_session: SessionT) -> bool: ...

    @abstractmethod
    def _abandon_event_type(self) -> EventTypeT: ...

    @abstractmethod
    def _abandon_event_value(self) -> str: ...

    @abstractmethod
    def _mark_abandoned(self, creative_session: SessionT, now: Any) -> None: ...

    @abstractmethod
    def _mark_expired(self, creative_session: SessionT) -> None: ...

    @abstractmethod
    def _started_at(self, creative_session: SessionT) -> Any: ...

    @abstractmethod
    def _client_occurred_at(self, payload: EventRequestT) -> Any | None: ...

    @abstractmethod
    def _event_metadata(self, payload: EventRequestT) -> dict[str, Any] | None: ...


def validate_timer_selection(mode: TimerMode, seconds: int | None) -> None:
    """Validate creative session timer mode/seconds combination."""
    if mode == TimerMode.no_timer:
        if seconds is not None:
            raise AppError(
                code="invalid_timer_selection",
                message="Timer mode and selected seconds are inconsistent.",
                status_code=422,
            )
        return
    if mode == TimerMode.countdown:
        if seconds not in ALLOWED_TIMER_SECONDS:
            raise AppError(
                code="invalid_timer_selection",
                message="Timer mode and selected seconds are inconsistent.",
                status_code=422,
            )
        return
    raise AppError(
        code="invalid_timer_selection",
        message="Timer mode and selected seconds are inconsistent.",
        status_code=422,
    )


def hash_create_request_payload(payload: Any) -> str:
    canonical = json.dumps(payload.model_dump(mode="json"), sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()
