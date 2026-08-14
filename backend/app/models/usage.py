from __future__ import annotations

from datetime import datetime
from uuid import UUID, uuid4

from sqlalchemy import DateTime, Index, Integer, String, func
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.types import Uuid

from app.db.base import Base


class AiUsageEvent(Base):
    """不含用户、提示词、密钥和业务正文的 AI 用量事件。"""

    __tablename__ = "ai_usage_events"
    __table_args__ = (
        Index("ix_ai_usage_created", "created_at"),
        Index(
            "ix_ai_usage_provider_model_created",
            "provider",
            "model",
            "created_at",
        ),
        Index(
            "ix_ai_usage_capability_created",
            "capability",
            "created_at",
        ),
    )

    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    provider: Mapped[str] = mapped_column(String(32), nullable=False)
    model: Mapped[str] = mapped_column(String(80), nullable=False)
    capability: Mapped[str | None] = mapped_column(String(32))
    prompt_contract_version: Mapped[str | None] = mapped_column(String(64))
    input_tokens: Mapped[int | None] = mapped_column(Integer)
    output_tokens: Mapped[int | None] = mapped_column(Integer)
    prompt_cache_hit_tokens: Mapped[int | None] = mapped_column(Integer)
    prompt_cache_miss_tokens: Mapped[int | None] = mapped_column(Integer)
    latency_ms: Mapped[int] = mapped_column(Integer, nullable=False)
    result_code: Mapped[str] = mapped_column(String(64), nullable=False)
    request_id: Mapped[str | None] = mapped_column(String(80))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
    )
