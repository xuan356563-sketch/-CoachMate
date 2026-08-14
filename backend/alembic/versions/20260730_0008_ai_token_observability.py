"""扩展不含身份与正文的 AI Token 可观测维度。

Revision ID: 20260730_0008
Revises: 20260728_0007
Create Date: 2026-07-30 00:00:00

只增加能力、提示词契约版本和供应商前缀缓存 Token 数，不保存用户、
提示词、回复、图片、语音或任何业务正文。
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "20260730_0008"
down_revision: str | Sequence[str] | None = "20260728_0007"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """新增可空聚合维度，兼容所有历史用量记录。"""
    with op.batch_alter_table("ai_usage_events") as batch_op:
        batch_op.add_column(
            sa.Column("capability", sa.String(length=32), nullable=True),
        )
        batch_op.add_column(
            sa.Column(
                "prompt_contract_version",
                sa.String(length=64),
                nullable=True,
            ),
        )
        batch_op.add_column(
            sa.Column("prompt_cache_hit_tokens", sa.Integer(), nullable=True),
        )
        batch_op.add_column(
            sa.Column("prompt_cache_miss_tokens", sa.Integer(), nullable=True),
        )
        batch_op.create_index(
            "ix_ai_usage_capability_created",
            ["capability", "created_at"],
        )


def downgrade() -> None:
    """仅移除新增聚合维度，保留原始 AI 用量事件。"""
    with op.batch_alter_table("ai_usage_events") as batch_op:
        batch_op.drop_index("ix_ai_usage_capability_created")
        batch_op.drop_column("prompt_cache_miss_tokens")
        batch_op.drop_column("prompt_cache_hit_tokens")
        batch_op.drop_column("prompt_contract_version")
        batch_op.drop_column("capability")
