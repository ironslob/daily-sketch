"""Create user_blocks, reports, and moderation_actions tables.

Revision ID: 0010_blocks_reports
Revises: 0009_avatar_upload_fk
Create Date: 2026-07-19
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = "0010_blocks_reports"
down_revision: str | None = "0009_avatar_upload_fk"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

report_target_type = postgresql.ENUM(
    "submission",
    "reflection",
    "profile",
    name="report_target_type",
    create_type=False,
)

report_reason = postgresql.ENUM(
    "inappropriate",
    "harassment",
    "hate",
    "spam",
    "intellectual_property",
    "self_harm",
    "other",
    name="report_reason",
    create_type=False,
)

report_status = postgresql.ENUM(
    "open",
    "reviewing",
    "resolved",
    "dismissed",
    name="report_status",
    create_type=False,
)

moderation_action_type = postgresql.ENUM(
    "hide_submission",
    "remove_submission",
    "restore_submission",
    "hide_reflection",
    "remove_reflection",
    "restore_reflection",
    "suspend_user",
    "restore_user",
    "resolve_report",
    "dismiss_report",
    name="moderation_action_type",
    create_type=False,
)


def upgrade() -> None:
    bind = op.get_bind()
    postgresql.ENUM(
        "submission",
        "reflection",
        "profile",
        name="report_target_type",
    ).create(bind, checkfirst=True)
    postgresql.ENUM(
        "inappropriate",
        "harassment",
        "hate",
        "spam",
        "intellectual_property",
        "self_harm",
        "other",
        name="report_reason",
    ).create(bind, checkfirst=True)
    postgresql.ENUM(
        "open",
        "reviewing",
        "resolved",
        "dismissed",
        name="report_status",
    ).create(bind, checkfirst=True)
    postgresql.ENUM(
        "hide_submission",
        "remove_submission",
        "restore_submission",
        "hide_reflection",
        "remove_reflection",
        "restore_reflection",
        "suspend_user",
        "restore_user",
        "resolve_report",
        "dismiss_report",
        name="moderation_action_type",
    ).create(bind, checkfirst=True)

    op.create_table(
        "user_blocks",
        sa.Column("blocker_user_id", sa.Uuid(), nullable=False),
        sa.Column("blocked_user_id", sa.Uuid(), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(["blocker_user_id"], ["users.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["blocked_user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("blocker_user_id", "blocked_user_id"),
        sa.CheckConstraint(
            "blocker_user_id <> blocked_user_id",
            name="ck_user_blocks_not_self",
        ),
    )
    op.create_index("ix_user_blocks_blocker_user_id", "user_blocks", ["blocker_user_id"])
    op.create_index("ix_user_blocks_blocked_user_id", "user_blocks", ["blocked_user_id"])

    op.create_table(
        "reports",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("reporter_user_id", sa.Uuid(), nullable=False),
        sa.Column("target_type", report_target_type, nullable=False),
        sa.Column("target_id", sa.Uuid(), nullable=False),
        sa.Column("reason", report_reason, nullable=False),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.Column("status", report_status, nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column("reviewed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("reviewed_by_user_id", sa.Uuid(), nullable=True),
        sa.Column("resolution_notes", sa.Text(), nullable=True),
        sa.ForeignKeyConstraint(["reporter_user_id"], ["users.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["reviewed_by_user_id"], ["users.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_reports_status_created_at",
        "reports",
        ["status", sa.text("created_at")],
    )
    op.create_index(
        "ix_reports_reporter_target_open",
        "reports",
        ["reporter_user_id", "target_type", "target_id"],
        postgresql_where=sa.text("status = 'open'"),
    )

    op.create_table(
        "moderation_actions",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("operator_identity", sa.Text(), nullable=False),
        sa.Column("action", moderation_action_type, nullable=False),
        sa.Column("target_type", report_target_type, nullable=False),
        sa.Column("target_id", sa.Uuid(), nullable=False),
        sa.Column("reason", sa.Text(), nullable=False),
        sa.Column("report_id", sa.Uuid(), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(["report_id"], ["reports.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_moderation_actions_created_at",
        "moderation_actions",
        [sa.text("created_at DESC")],
    )


def downgrade() -> None:
    op.drop_index("ix_moderation_actions_created_at", table_name="moderation_actions")
    op.drop_table("moderation_actions")
    op.drop_index("ix_reports_reporter_target_open", table_name="reports")
    op.drop_index("ix_reports_status_created_at", table_name="reports")
    op.drop_table("reports")
    op.drop_index("ix_user_blocks_blocked_user_id", table_name="user_blocks")
    op.drop_index("ix_user_blocks_blocker_user_id", table_name="user_blocks")
    op.drop_table("user_blocks")

    bind = op.get_bind()
    postgresql.ENUM(name="moderation_action_type").drop(bind, checkfirst=True)
    postgresql.ENUM(name="report_status").drop(bind, checkfirst=True)
    postgresql.ENUM(name="report_reason").drop(bind, checkfirst=True)
    postgresql.ENUM(name="report_target_type").drop(bind, checkfirst=True)
