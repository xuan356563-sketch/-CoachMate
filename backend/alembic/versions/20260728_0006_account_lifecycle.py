"""建立账号导出与延迟删除生命周期表。

Revision ID: 20260728_0006
Revises: 20260728_0005
Create Date: 2026-07-28 00:00:00

导出正文不落库。删除申请立即撤销会话，保留 7 天可撤销任务；永久删除后只
保留随机删除请求标识和完成时间，不保留 user_id、邮箱、手机号或业务数据。
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "20260728_0006"
down_revision: str | Sequence[str] | None = "20260728_0005"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """新增导出审计、删除复核、撤销期任务和匿名回执。"""
    op.create_table(
        "account_export_records",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("export_format", sa.String(length=16), nullable=False),
        sa.Column("state", sa.String(length=16), nullable=False),
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
        "ix_account_exports_user_created",
        "account_export_records",
        ["user_id", "created_at"],
    )
    op.create_table(
        "account_deletion_challenges",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("email_hash", sa.String(length=64), nullable=False),
        sa.Column("code_hash", sa.String(length=64), nullable=False),
        sa.Column(
            "attempt_count",
            sa.Integer(),
            server_default="0",
            nullable=False,
        ),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("CURRENT_TIMESTAMP"),
            nullable=False,
        ),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("consumed_at", sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_account_deletion_challenges_user_created",
        "account_deletion_challenges",
        ["user_id", "created_at"],
    )
    op.create_table(
        "account_deletion_requests",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("status", sa.String(length=16), nullable=False),
        sa.Column(
            "requested_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("CURRENT_TIMESTAMP"),
            nullable=False,
        ),
        sa.Column("purge_after", sa.DateTime(timezone=True), nullable=False),
        sa.Column("cancelled_at", sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_account_deletion_requests_status_due",
        "account_deletion_requests",
        ["status", "purge_after"],
    )
    op.create_index(
        "ix_account_deletion_requests_user_created",
        "account_deletion_requests",
        ["user_id", "requested_at"],
    )
    op.create_table(
        "account_deletion_receipts",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("deletion_request_id", sa.Uuid(), nullable=False),
        sa.Column(
            "completed_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("CURRENT_TIMESTAMP"),
            nullable=False,
        ),
        sa.PrimaryKeyConstraint("id"),
    )


def downgrade() -> None:
    """删除审计和回执不可自动降级，应用回滚不应破坏撤销期。"""
    raise RuntimeError(
        "账号生命周期迁移禁止自动降级；请保留删除任务并完成人工影响评估"
    )
