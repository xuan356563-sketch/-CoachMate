"""建立不含身份与正文的 AI 用量事件表。

Revision ID: 20260728_0007
Revises: 20260728_0006
Create Date: 2026-07-28 00:00:00

仅保存供应商、模型、Token 数、耗时、结果码和安全请求 ID。不得增加用户、
邮箱、提示词、模型响应、图片、语音或密钥字段。
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "20260728_0007"
down_revision: str | Sequence[str] | None = "20260728_0006"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """新增最小 AI 用量事件表。"""
    op.create_table(
        "ai_usage_events",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("provider", sa.String(length=32), nullable=False),
        sa.Column("model", sa.String(length=80), nullable=False),
        sa.Column("input_tokens", sa.Integer(), nullable=True),
        sa.Column("output_tokens", sa.Integer(), nullable=True),
        sa.Column("latency_ms", sa.Integer(), nullable=False),
        sa.Column("result_code", sa.String(length=64), nullable=False),
        sa.Column("request_id", sa.String(length=80), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("CURRENT_TIMESTAMP"),
            nullable=False,
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_ai_usage_created",
        "ai_usage_events",
        ["created_at"],
    )
    op.create_index(
        "ix_ai_usage_provider_model_created",
        "ai_usage_events",
        ["provider", "model", "created_at"],
    )


def downgrade() -> None:
    """用量审计不可自动降级，回退应用时保留历史聚合依据。"""
    raise RuntimeError(
        "AI 用量迁移禁止自动降级；请先完成审计保留期与备份评估"
    )
