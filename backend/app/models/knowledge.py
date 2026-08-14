from __future__ import annotations

from sqlalchemy import JSON, String
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base

_knowledge_json = JSON().with_variant(JSONB, "postgresql")


class KnowledgePrincipleRecord(Base):
    """自编训练原则，只保存短摘要和来源定位，不保存书籍原文。"""

    __tablename__ = "knowledge_principles"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    status: Mapped[str] = mapped_column(String(16), nullable=False)
    title: Mapped[str] = mapped_column(String(120), nullable=False)
    summary: Mapped[str] = mapped_column(String(500), nullable=False)
    tags: Mapped[list[str]] = mapped_column(_knowledge_json, nullable=False)
    source_label: Mapped[str] = mapped_column(String(160), nullable=False)
    source_section: Mapped[str] = mapped_column(String(160), nullable=False)
    content_version: Mapped[str] = mapped_column(String(32), nullable=False)


class TrainingTemplateRecord(Base):
    """可确定性匹配和本地编译的结构化训练模板。"""

    __tablename__ = "training_templates"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    status: Mapped[str] = mapped_column(String(16), nullable=False)
    title: Mapped[str] = mapped_column(String(120), nullable=False)
    population_template_id: Mapped[str] = mapped_column(
        String(64),
        nullable=False,
    )
    goals: Mapped[list[str]] = mapped_column(_knowledge_json, nullable=False)
    primary_sports: Mapped[list[str]] = mapped_column(
        _knowledge_json,
        nullable=False,
    )
    supported_days: Mapped[list[int]] = mapped_column(
        _knowledge_json,
        nullable=False,
    )
    required_equipment: Mapped[list[str]] = mapped_column(
        _knowledge_json,
        nullable=False,
    )
    session_pattern: Mapped[list[str]] = mapped_column(
        _knowledge_json,
        nullable=False,
    )
    source_label: Mapped[str] = mapped_column(String(160), nullable=False)
    content_version: Mapped[str] = mapped_column(String(32), nullable=False)
