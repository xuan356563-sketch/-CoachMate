"""新增加密云端用户档案。

Revision ID: 20260731_0010
Revises: 20260730_0009
Create Date: 2026-07-31 09:00:00
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "20260731_0010"
down_revision: str | Sequence[str] | None = "20260730_0009"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """只增加密文档案表，不修改旧同步投影。"""
    op.create_table(
        "cloud_user_profiles",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("version", sa.Integer(), nullable=False),
        sa.Column("schema_version", sa.Integer(), nullable=False),
        sa.Column("ciphertext", sa.LargeBinary(), nullable=False),
        sa.Column("nonce", sa.LargeBinary(length=12), nullable=False),
        sa.Column("key_version", sa.String(length=64), nullable=False),
        sa.Column("health_fields_included", sa.Boolean(), nullable=False),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("user_id", name="uq_cloud_user_profiles_user"),
    )


def downgrade() -> None:
    """测试环境允许回退；生产回滚只关闭功能开关并保留密文。"""
    op.drop_table("cloud_user_profiles")
