"""新增已审核训练原则与结构化计划模板。

Revision ID: 20260730_0009
Revises: 20260730_0008
Create Date: 2026-07-30 01:00:00
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "20260730_0009"
down_revision: str | Sequence[str] | None = "20260730_0008"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """创建不含版权正文和用户数据的知识目录。"""
    op.create_table(
        "knowledge_principles",
        sa.Column("id", sa.String(length=64), nullable=False),
        sa.Column("status", sa.String(length=16), nullable=False),
        sa.Column("title", sa.String(length=120), nullable=False),
        sa.Column("summary", sa.String(length=500), nullable=False),
        sa.Column("tags", sa.JSON(), nullable=False),
        sa.Column("source_label", sa.String(length=160), nullable=False),
        sa.Column("source_section", sa.String(length=160), nullable=False),
        sa.Column("content_version", sa.String(length=32), nullable=False),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_table(
        "training_templates",
        sa.Column("id", sa.String(length=64), nullable=False),
        sa.Column("status", sa.String(length=16), nullable=False),
        sa.Column("title", sa.String(length=120), nullable=False),
        sa.Column(
            "population_template_id",
            sa.String(length=64),
            nullable=False,
        ),
        sa.Column("goals", sa.JSON(), nullable=False),
        sa.Column("primary_sports", sa.JSON(), nullable=False),
        sa.Column("supported_days", sa.JSON(), nullable=False),
        sa.Column("required_equipment", sa.JSON(), nullable=False),
        sa.Column("session_pattern", sa.JSON(), nullable=False),
        sa.Column("source_label", sa.String(length=160), nullable=False),
        sa.Column("content_version", sa.String(length=32), nullable=False),
        sa.PrimaryKeyConstraint("id"),
    )


def downgrade() -> None:
    """知识目录为可重建种子数据，允许安全回退。"""
    op.drop_table("training_templates")
    op.drop_table("knowledge_principles")
