"""建立后端迁移基线。

Revision ID: 20260712_0001
Revises:
Create Date: 2026-07-12 00:00:00

本版本刻意不创建业务表。账号、敏感健康数据和同步表必须在各自
功能切片实施时，通过独立迁移、兼容说明和回滚方案进入数据库。
"""

from collections.abc import Sequence

revision: str = "20260712_0001"
down_revision: str | Sequence[str] | None = None
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """登记迁移历史起点，不创建业务数据结构。"""


def downgrade() -> None:
    """回退迁移历史起点，不删除业务数据结构。"""
