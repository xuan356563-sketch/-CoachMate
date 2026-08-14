from __future__ import annotations

import importlib.util
from pathlib import Path
from types import ModuleType

import sqlalchemy as sa
from alembic.migration import MigrationContext
from alembic.operations import Operations
from sqlalchemy import inspect, select
from sqlalchemy.orm import Session

from app.db.base import Base
from app.models.usage import AiUsageEvent
from app.services.ai_usage import AiUsageRecorder

VERSIONS = Path(__file__).parents[1] / "alembic" / "versions"


def _load_migration(filename: str) -> ModuleType:
    path = VERSIONS / filename
    spec = importlib.util.spec_from_file_location(path.stem, path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_token_observability_migration_adds_only_safe_dimensions() -> None:
    engine = sa.create_engine("sqlite+pysqlite://")
    with engine.begin() as connection:
        initial = _load_migration("20260728_0007_ai_usage.py")
        initial.op = Operations(MigrationContext.configure(connection))
        initial.upgrade()
        migration = _load_migration("20260730_0008_ai_token_observability.py")
        migration.op = Operations(MigrationContext.configure(connection))
        migration.upgrade()
        columns = {
            column["name"]
            for column in inspect(connection).get_columns("ai_usage_events")
        }
        migration.downgrade()
        rolled_back_columns = {
            column["name"]
            for column in inspect(connection).get_columns("ai_usage_events")
        }

    assert migration.down_revision == "20260728_0007"
    assert {
        "capability",
        "prompt_contract_version",
        "prompt_cache_hit_tokens",
        "prompt_cache_miss_tokens",
    }.issubset(columns)
    assert columns.isdisjoint({"user_id", "prompt", "payload", "response"})
    assert "provider" in rolled_back_columns
    assert "capability" not in rolled_back_columns
    engine.dispose()


def test_usage_recorder_persists_cache_dimensions_without_business_content() -> None:
    engine = sa.create_engine("sqlite+pysqlite://")
    Base.metadata.create_all(engine)
    with Session(engine) as session:
        AiUsageRecorder(session).record(
            provider="deepseek",
            model="deepseek-v4-flash",
            capability="chat",
            prompt_contract_version="chat-v2",
            input_tokens=280,
            output_tokens=36,
            prompt_cache_hit_tokens=200,
            prompt_cache_miss_tokens=80,
            latency_ms=120,
            result_code="generated",
            request_id="safe-request-1",
        )
        event = session.scalar(select(AiUsageEvent))

    assert event is not None
    assert event.capability == "chat"
    assert event.prompt_contract_version == "chat-v2"
    assert event.prompt_cache_hit_tokens == 200
    assert event.prompt_cache_miss_tokens == 80
    Base.metadata.drop_all(engine)
    engine.dispose()
