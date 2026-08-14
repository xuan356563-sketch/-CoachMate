from __future__ import annotations

from datetime import date, datetime
from uuid import UUID, uuid4

from sqlalchemy import (
    JSON,
    BigInteger,
    Boolean,
    Date,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    LargeBinary,
    String,
    UniqueConstraint,
    func,
)
from sqlalchemy.dialects import postgresql
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.types import Uuid

from app.db.base import Base

_json_type = JSON().with_variant(
    postgresql.JSONB(astext_type=String()),
    "postgresql",
)
_cursor_type = BigInteger().with_variant(Integer(), "sqlite")


class TrainingPreference(Base):
    """用户主动启用云同步后保存的训练偏好白名单投影。"""

    __tablename__ = "training_preferences"
    __table_args__ = (
        UniqueConstraint("user_id", name="uq_training_preferences_user"),
    )

    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    user_id: Mapped[UUID] = mapped_column(
        Uuid,
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    version: Mapped[int] = mapped_column(Integer, nullable=False)
    goal: Mapped[str] = mapped_column(String(80), nullable=False)
    sport_types: Mapped[list[str]] = mapped_column(_json_type, nullable=False)
    experience_level: Mapped[str] = mapped_column(String(32), nullable=False)
    weekly_availability: Mapped[list[int]] = mapped_column(
        _json_type,
        nullable=False,
    )
    equipment: Mapped[list[str]] = mapped_column(_json_type, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
        nullable=False,
    )


class CloudUserProfile(Base):
    """确认后以 AES-GCM 密文保存的用户档案。"""

    __tablename__ = "cloud_user_profiles"
    __table_args__ = (
        UniqueConstraint("user_id", name="uq_cloud_user_profiles_user"),
    )

    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    user_id: Mapped[UUID] = mapped_column(
        Uuid,
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    version: Mapped[int] = mapped_column(Integer, nullable=False)
    schema_version: Mapped[int] = mapped_column(Integer, nullable=False)
    ciphertext: Mapped[bytes] = mapped_column(LargeBinary, nullable=False)
    nonce: Mapped[bytes] = mapped_column(LargeBinary(12), nullable=False)
    key_version: Mapped[str] = mapped_column(String(64), nullable=False)
    health_fields_included: Mapped[bool] = mapped_column(
        Boolean,
        default=False,
        nullable=False,
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
        nullable=False,
    )


class CloudPlanVersion(Base):
    """不含健康和身体数据的计划版本投影。"""

    __tablename__ = "cloud_plan_versions"
    __table_args__ = (
        Index("ix_cloud_plan_versions_user_updated", "user_id", "updated_at"),
    )

    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    user_id: Mapped[UUID] = mapped_column(
        Uuid,
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    version: Mapped[int] = mapped_column(Integer, nullable=False)
    title: Mapped[str] = mapped_column(String(120), nullable=False)
    starts_on: Mapped[date] = mapped_column(Date, nullable=False)
    ends_on: Mapped[date | None] = mapped_column(Date)
    state: Mapped[str] = mapped_column(String(24), nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
        nullable=False,
    )


class CloudScheduledWorkout(Base):
    """计划课次的最小跨设备投影。"""

    __tablename__ = "cloud_scheduled_workouts"
    __table_args__ = (
        Index(
            "ix_cloud_scheduled_workouts_user_date",
            "user_id",
            "scheduled_date",
        ),
    )

    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    user_id: Mapped[UUID] = mapped_column(
        Uuid,
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    plan_version_id: Mapped[UUID] = mapped_column(Uuid, nullable=False)
    version: Mapped[int] = mapped_column(Integer, nullable=False)
    scheduled_date: Mapped[date] = mapped_column(Date, nullable=False)
    sport_type: Mapped[str] = mapped_column(String(32), nullable=False)
    title: Mapped[str] = mapped_column(String(120), nullable=False)
    duration_minutes: Mapped[int] = mapped_column(Integer, nullable=False)
    state: Mapped[str] = mapped_column(String(24), nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
        nullable=False,
    )


class CompletionSummary(Base):
    """不含 RPE、备注、心率、路线或重量的训练完成摘要。"""

    __tablename__ = "completion_summaries"
    __table_args__ = (
        Index(
            "ix_completion_summaries_user_started",
            "user_id",
            "started_at",
        ),
    )

    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    user_id: Mapped[UUID] = mapped_column(
        Uuid,
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    plan_version_id: Mapped[UUID] = mapped_column(Uuid, nullable=False)
    scheduled_workout_id: Mapped[UUID] = mapped_column(Uuid, nullable=False)
    started_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
    )
    ended_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
    )
    duration_seconds: Mapped[int] = mapped_column(Integer, nullable=False)
    completion_percentage: Mapped[int] = mapped_column(Integer, nullable=False)
    revoked: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
    )


class UserAppSetting(Base):
    """仅保存与跨设备体验有关的非敏感应用设置。"""

    __tablename__ = "user_app_settings"
    __table_args__ = (
        UniqueConstraint("user_id", name="uq_user_app_settings_user"),
    )

    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    user_id: Mapped[UUID] = mapped_column(
        Uuid,
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    version: Mapped[int] = mapped_column(Integer, nullable=False)
    locale: Mapped[str] = mapped_column(String(16), nullable=False)
    week_starts_on: Mapped[int] = mapped_column(Integer, nullable=False)
    notifications_enabled: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
        nullable=False,
    )


class SyncMutation(Base):
    """按账号保存同步请求结果，使客户端重试保持幂等。"""

    __tablename__ = "sync_mutations"
    __table_args__ = (
        UniqueConstraint(
            "user_id",
            "mutation_id",
            name="uq_sync_mutations_user_mutation",
        ),
        Index("ix_sync_mutations_user_created", "user_id", "created_at"),
    )

    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    user_id: Mapped[UUID] = mapped_column(
        Uuid,
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    mutation_id: Mapped[UUID] = mapped_column(Uuid, nullable=False)
    entity_type: Mapped[str] = mapped_column(String(32), nullable=False)
    entity_id: Mapped[UUID] = mapped_column(Uuid, nullable=False)
    outcome: Mapped[str] = mapped_column(String(16), nullable=False)
    result_payload: Mapped[dict[str, object]] = mapped_column(
        _json_type,
        nullable=False,
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
    )


class SyncChange(Base):
    """为每个账号提供单调递增的增量同步游标。"""

    __tablename__ = "sync_changes"
    __table_args__ = (
        Index("ix_sync_changes_user_cursor", "user_id", "cursor"),
    )

    cursor: Mapped[int] = mapped_column(
        _cursor_type,
        primary_key=True,
        autoincrement=True,
    )
    user_id: Mapped[UUID] = mapped_column(
        Uuid,
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    mutation_id: Mapped[UUID] = mapped_column(Uuid, nullable=False)
    entity_type: Mapped[str] = mapped_column(String(32), nullable=False)
    entity_id: Mapped[UUID] = mapped_column(Uuid, nullable=False)
    operation: Mapped[str] = mapped_column(String(16), nullable=False)
    version: Mapped[int] = mapped_column(Integer, nullable=False)
    payload: Mapped[dict[str, object]] = mapped_column(_json_type, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
    )
