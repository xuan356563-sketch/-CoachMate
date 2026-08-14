"""增量增加邮箱验证码登录能力。

Revision ID: 20260716_0004
Revises: 20260713_0003
Create Date: 2026-07-16 00:00:00

本迁移保留既有手机号身份、设备、同意记录和会话。邮箱和验证码仅保存
HMAC 摘要，用户表只新增脱敏邮箱提示。生产环境不得在存在邮箱专属账号时
直接降级，否则会破坏账号身份。
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "20260716_0004"
down_revision: str | Sequence[str] | None = "20260713_0003"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """扩展用户身份并创建邮箱验证码挑战表。"""
    op.add_column(
        "users",
        sa.Column("email_hash", sa.String(length=64), nullable=True),
    )
    op.add_column(
        "users",
        sa.Column("masked_email", sa.String(length=320), nullable=True),
    )
    op.create_unique_constraint("uq_users_email_hash", "users", ["email_hash"])
    op.alter_column(
        "users",
        "phone_hash",
        existing_type=sa.String(length=64),
        nullable=True,
    )
    op.alter_column(
        "users",
        "phone_last4",
        existing_type=sa.String(length=4),
        nullable=True,
    )
    op.create_check_constraint(
        "ck_users_has_identity",
        "users",
        "phone_hash IS NOT NULL OR email_hash IS NOT NULL",
    )

    op.create_table(
        "email_challenges",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("email_hash", sa.String(length=64), nullable=False),
        sa.Column("code_hash", sa.String(length=64), nullable=False),
        sa.Column("attempt_count", sa.Integer(), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("CURRENT_TIMESTAMP"),
            nullable=False,
        ),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("consumed_at", sa.DateTime(timezone=True), nullable=True),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_email_challenges_email_created",
        "email_challenges",
        ["email_hash", "created_at"],
    )


def downgrade() -> None:
    """拒绝自动删除邮箱身份数据；生产回滚只关闭入口并回退应用。"""
    raise RuntimeError(
        "邮箱认证迁移禁止自动降级；请先完成人工数据迁移、会话影响评估和备份"
    )
