from __future__ import annotations

from datetime import datetime
from uuid import UUID, uuid4

from sqlalchemy import DateTime, ForeignKey, Index, String, UniqueConstraint, func
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.types import Uuid

from app.db.base import Base


class SubscriptionEntitlement(Base):
    """服务端裁决后的订阅权益，不保存完整商店载荷。"""

    __tablename__ = "subscription_entitlements"
    __table_args__ = (
        UniqueConstraint("user_id", "platform", name="uq_entitlement_user_platform"),
        UniqueConstraint(
            "original_transaction_id",
            name="uq_entitlement_original_transaction",
        ),
        Index("ix_entitlement_user_status", "user_id", "status"),
    )

    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    user_id: Mapped[UUID] = mapped_column(
        Uuid,
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    platform: Mapped[str] = mapped_column(String(16), nullable=False)
    product_id: Mapped[str] = mapped_column(String(160), nullable=False)
    transaction_id: Mapped[str] = mapped_column(String(128), nullable=False)
    original_transaction_id: Mapped[str] = mapped_column(String(128), nullable=False)
    environment: Mapped[str] = mapped_column(String(16), nullable=False)
    status: Mapped[str] = mapped_column(String(24), nullable=False)
    purchased_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
    )
    expires_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    last_verified_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
    )


class AppleSubscriptionEvent(Base):
    """只保存苹果通知摘要，用于幂等和审计。"""

    __tablename__ = "apple_subscription_events"

    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    notification_uuid: Mapped[str] = mapped_column(
        String(128),
        unique=True,
        nullable=False,
    )
    user_id: Mapped[UUID | None] = mapped_column(
        Uuid,
        ForeignKey("users.id", ondelete="SET NULL"),
    )
    notification_type: Mapped[str] = mapped_column(String(64), nullable=False)
    subtype: Mapped[str | None] = mapped_column(String(64))
    payload_hash: Mapped[str] = mapped_column(String(64), nullable=False)
    processed_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
    )
