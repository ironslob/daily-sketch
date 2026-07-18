"""Create sketch_sessions and sketch_session_events tables.

Revision ID: 0005_sketch_sessions
Revises: 0004_daily_prompts
Create Date: 2026-07-18
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = "0005_sketch_sessions"
down_revision: str | None = "0004_daily_prompts"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

timer_mode = postgresql.ENUM(
    "countdown",
    "no_timer",
    name="timer_mode",
    create_type=False,
)

sketch_session_status = postgresql.ENUM(
    "active",
    "paused",
    "ready_for_photo",
    "uploading",
    "completed",
    "abandoned",
    "expired",
    name="sketch_session_status",
    create_type=False,
)

sketch_session_event_type = postgresql.ENUM(
    "started",
    "paused",
    "resumed",
    "timer_completed",
    "finished_early",
    "photo_step_reached",
    "upload_started",
    "upload_completed",
    "submission_created",
    "abandoned",
    name="sketch_session_event_type",
    create_type=False,
)


def upgrade() -> None:
    bind = op.get_bind()
    # Reuse timer_mode from 0003; ensure it exists if the DB was recreated/stamped.
    postgresql.ENUM(
        "countdown",
        "no_timer",
        name="timer_mode",
    ).create(bind, checkfirst=True)
    postgresql.ENUM(
        "active",
        "paused",
        "ready_for_photo",
        "uploading",
        "completed",
        "abandoned",
        "expired",
        name="sketch_session_status",
    ).create(bind, checkfirst=True)
    postgresql.ENUM(
        "started",
        "paused",
        "resumed",
        "timer_completed",
        "finished_early",
        "photo_step_reached",
        "upload_started",
        "upload_completed",
        "submission_created",
        "abandoned",
        name="sketch_session_event_type",
    ).create(bind, checkfirst=True)

    op.create_table(
        "sketch_sessions",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("prompt_id", sa.Uuid(), nullable=False),
        sa.Column("timer_mode", timer_mode, nullable=False),
        sa.Column("selected_timer_seconds", sa.Integer(), nullable=True),
        sa.Column("status", sketch_session_status, nullable=False),
        sa.Column("started_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("paused_total_seconds", sa.Integer(), nullable=False),
        sa.Column("timer_completed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("finish_requested_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("photo_step_reached_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("upload_started_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("upload_completed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("completed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("abandoned_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["prompt_id"], ["daily_prompts.id"], ondelete="RESTRICT"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_sketch_sessions_user_id_created_at",
        "sketch_sessions",
        ["user_id", sa.text("created_at DESC")],
    )
    op.create_index(
        "ix_sketch_sessions_prompt_id_created_at",
        "sketch_sessions",
        ["prompt_id", sa.text("created_at DESC")],
    )

    op.create_table(
        "sketch_session_events",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("sketch_session_id", sa.Uuid(), nullable=False),
        sa.Column("event_type", sketch_session_event_type, nullable=False),
        sa.Column("occurred_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("client_occurred_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "metadata_json",
            postgresql.JSONB(astext_type=sa.Text()),
            server_default=sa.text("'{}'::jsonb"),
            nullable=False,
        ),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(
            ["sketch_session_id"],
            ["sketch_sessions.id"],
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_sketch_session_events_sketch_session_id",
        "sketch_session_events",
        ["sketch_session_id"],
    )


def downgrade() -> None:
    op.drop_index(
        "ix_sketch_session_events_sketch_session_id",
        table_name="sketch_session_events",
    )
    op.drop_table("sketch_session_events")
    op.drop_index(
        "ix_sketch_sessions_prompt_id_created_at",
        table_name="sketch_sessions",
    )
    op.drop_index(
        "ix_sketch_sessions_user_id_created_at",
        table_name="sketch_sessions",
    )
    op.drop_table("sketch_sessions")
    postgresql.ENUM(name="sketch_session_event_type").drop(op.get_bind(), checkfirst=True)
    postgresql.ENUM(name="sketch_session_status").drop(op.get_bind(), checkfirst=True)
