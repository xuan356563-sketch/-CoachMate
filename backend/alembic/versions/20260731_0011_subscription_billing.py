"""新增苹果订阅权益与通知幂等表。

Revision ID: 20260731_0011
Revises: 20260731_0010
Create Date: 2026-07-31 09:30:00
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "20260731_0011"
down_revision: str | Sequence[str] | None = "20260731_0010"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "subscription_entitlements",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("platform", sa.String(length=16), nullable=False),
        sa.Column("product_id", sa.String(length=160), nullable=False),
        sa.Column("transaction_id", sa.String(length=128), nullable=False),
        sa.Column("original_transaction_id", sa.String(length=128), nullable=False),
        sa.Column("environment", sa.String(length=16), nullable=False),
        sa.Column("status", sa.String(length=24), nullable=False),
        sa.Column("purchased_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("revoked_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "last_verified_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "original_transaction_id",
            name="uq_entitlement_original_transaction",
        ),
        sa.UniqueConstraint(
            "user_id",
            "platform",
            name="uq_entitlement_user_platform",
        ),
    )
    op.create_index(
        "ix_entitlement_user_status",
        "subscription_entitlements",
        ["user_id", "status"],
    )
    op.create_table(
        "apple_subscription_events",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("notification_uuid", sa.String(length=128), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=True),
        sa.Column("notification_type", sa.String(length=64), nullable=False),
        sa.Column("subtype", sa.String(length=64), nullable=True),
        sa.Column("payload_hash", sa.String(length=64), nullable=False),
        sa.Column(
            "processed_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("notification_uuid"),
    )


def downgrade() -> None:
    op.drop_table("apple_subscription_events")
    op.drop_index("ix_entitlement_user_status", table_name="subscription_entitlements")
    op.drop_table("subscription_entitlements")
