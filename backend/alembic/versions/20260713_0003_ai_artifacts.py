"""建立 AI 编排任务和跨设备产物表。

Revision ID: 20260713_0003
Revises: 20260713_0002
Create Date: 2026-07-13 00:00:00

本迁移只保存经服务端 Schema 校验后的 AI 产物、状态和上下文摘要。不保存
原始提示词、HealthKit 样本、语音、图片或视频。PostgreSQL 使用 JSONB；
SQLite 测试环境使用兼容 JSON。生产回滚前须先导出已接受的产物并完成影响评估。
"""

from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision: str = "20260713_0003"
down_revision: str | Sequence[str] | None = "20260713_0002"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

_json_type = sa.JSON().with_variant(postgresql.JSONB(astext_type=sa.Text()), "postgresql")


def upgrade() -> None:
    """创建 AI 任务与产物表，不改变既有账号或训练数据。"""
    op.create_table(
        "ai_generation_jobs",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("capability", sa.String(length=32), nullable=False),
        sa.Column("artifact_type", sa.String(length=64), nullable=False),
        sa.Column("provider", sa.String(length=32), nullable=False),
        sa.Column("model", sa.String(length=80), nullable=False),
        sa.Column("context_digest", sa.String(length=64), nullable=False),
        sa.Column("state", sa.String(length=16), nullable=False),
        sa.Column("error_code", sa.String(length=64), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("CURRENT_TIMESTAMP"),
            nullable=False,
        ),
        sa.Column("completed_at", sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_ai_generation_jobs_user_created",
        "ai_generation_jobs",
        ["user_id", "created_at"],
    )
    op.create_index(
        "ix_ai_generation_jobs_user_context",
        "ai_generation_jobs",
        ["user_id", "context_digest"],
    )
    op.create_table(
        "ai_artifacts",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("job_id", sa.Uuid(), nullable=True),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("capability", sa.String(length=32), nullable=False),
        sa.Column("artifact_type", sa.String(length=64), nullable=False),
        sa.Column("schema_version", sa.Integer(), nullable=False),
        sa.Column("decision_status", sa.String(length=16), nullable=False),
        sa.Column("context_digest", sa.String(length=64), nullable=False),
        sa.Column("payload", _json_type, nullable=False),
        sa.Column("warnings", _json_type, nullable=False),
        sa.Column("provider", sa.String(length=32), nullable=False),
        sa.Column("model", sa.String(length=80), nullable=False),
        sa.Column(
            "generated_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("CURRENT_TIMESTAMP"),
            nullable=False,
        ),
        sa.Column("decided_at", sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(
            ["job_id"],
            ["ai_generation_jobs.id"],
            ondelete="SET NULL",
        ),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_ai_artifacts_user_created",
        "ai_artifacts",
        ["user_id", "generated_at"],
    )
    op.create_index(
        "ix_ai_artifacts_user_capability_context",
        "ai_artifacts",
        ["user_id", "capability", "context_digest"],
    )


def downgrade() -> None:
    """仅在确认未使用生产 AI 产物后回退新增表。"""
    op.drop_index(
        "ix_ai_artifacts_user_capability_context",
        table_name="ai_artifacts",
    )
    op.drop_index("ix_ai_artifacts_user_created", table_name="ai_artifacts")
    op.drop_table("ai_artifacts")
    op.drop_index(
        "ix_ai_generation_jobs_user_context",
        table_name="ai_generation_jobs",
    )
    op.drop_index(
        "ix_ai_generation_jobs_user_created",
        table_name="ai_generation_jobs",
    )
    op.drop_table("ai_generation_jobs")
