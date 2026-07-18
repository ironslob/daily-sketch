"""Create daily_prompts table.

Revision ID: 0004_daily_prompts
Revises: 0003_user_preferences
Create Date: 2026-07-18
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = "0004_daily_prompts"
down_revision: str | None = "0003_user_preferences"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

prompt_status = postgresql.ENUM(
    "draft",
    "published",
    "withdrawn",
    name="prompt_status",
    create_type=False,
)


def upgrade() -> None:
    bind = op.get_bind()
    postgresql.ENUM(
        "draft",
        "published",
        "withdrawn",
        name="prompt_status",
    ).create(bind, checkfirst=True)

    op.create_table(
        "daily_prompts",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("prompt_date", sa.Date(), nullable=False),
        sa.Column("word_1", sa.Text(), nullable=False),
        sa.Column("word_2", sa.Text(), nullable=False),
        sa.Column("word_3", sa.Text(), nullable=False),
        sa.Column("status", prompt_status, nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column("published_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("corrected_at", sa.DateTime(timezone=True), nullable=True),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("prompt_date", name="uq_daily_prompts_prompt_date"),
    )


def downgrade() -> None:
    op.drop_table("daily_prompts")
    postgresql.ENUM(name="prompt_status").drop(op.get_bind(), checkfirst=True)
