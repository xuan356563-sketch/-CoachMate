from __future__ import annotations

import importlib.util
from collections.abc import Generator
from datetime import timedelta
from pathlib import Path
from types import ModuleType
from uuid import uuid4

import pytest
import sqlalchemy as sa
from alembic.migration import MigrationContext
from alembic.operations import Operations
from fastapi.testclient import TestClient
from sqlalchemy import inspect, select
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool

from app.core.config import Settings, get_settings
from app.core.security import utc_now
from app.db.base import Base
from app.db.session import get_session
from app.main import create_app
from app.models import AccountDeletionRequest, SyncMutation, User
from app.models.usage import AiUsageEvent
from app.ops_main import create_ops_app
from app.services.ai_usage import AiUsageRecorder

MIGRATION_PATH = (
    Path(__file__).parents[1]
    / "alembic"
    / "versions"
    / "20260728_0007_ai_usage.py"
)


def _load_migration() -> ModuleType:
    spec = importlib.util.spec_from_file_location(
        "ai_usage_migration",
        MIGRATION_PATH,
    )
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


@pytest.fixture
def ops_client() -> Generator[tuple[TestClient, Session], None, None]:
    engine = sa.create_engine(
        "sqlite+pysqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(engine)
    session_factory = sessionmaker(bind=engine)
    settings = Settings(ops_enabled=True, sync_enabled=True)
    app = create_ops_app()

    def get_test_session() -> Generator[Session, None, None]:
        with session_factory() as session:
            yield session

    app.dependency_overrides[get_session] = get_test_session
    app.dependency_overrides[get_settings] = lambda: settings
    seed_session = session_factory()
    try:
        with TestClient(app) as client:
            yield client, seed_session
    finally:
        seed_session.close()
        app.dependency_overrides.clear()
        Base.metadata.drop_all(engine)
        engine.dispose()


def test_ai_usage_migration_and_model_contain_only_aggregate_dimensions() -> None:
    """加入 user_id、提示词或密钥列时，此测试必须失败。"""
    engine = sa.create_engine("sqlite+pysqlite://")
    with engine.begin() as connection:
        migration = _load_migration()
        migration.op = Operations(MigrationContext.configure(connection))
        migration.upgrade()
        columns = {
            column["name"]
            for column in inspect(connection).get_columns("ai_usage_events")
        }
        assert columns == {
            "id",
            "provider",
            "model",
            "input_tokens",
            "output_tokens",
            "latency_ms",
            "result_code",
            "request_id",
            "created_at",
        }
        assert migration.down_revision == "20260728_0006"
    engine.dispose()


def test_ai_usage_recorder_persists_metrics_without_user_or_prompt() -> None:
    """记录器若复制请求正文而不是度量值，此测试必须失败。"""
    engine = sa.create_engine("sqlite+pysqlite://")
    Base.metadata.create_all(engine)
    with Session(engine) as session:
        AiUsageRecorder(session).record(
            provider="deepseek",
            model="deepseek-chat",
            input_tokens=120,
            output_tokens=45,
            latency_ms=321,
            result_code="generated",
            request_id="req-safe-001",
        )
        event = session.scalar(select(AiUsageEvent))
        assert event is not None
        assert event.input_tokens == 120
        assert event.output_tokens == 45
        assert event.latency_ms == 321
        assert event.result_code == "generated"
        assert {
            column.name for column in AiUsageEvent.__table__.columns
        }.isdisjoint({"user_id", "prompt", "payload", "api_key", "email"})
    Base.metadata.drop_all(engine)
    engine.dispose()


def test_ops_routes_are_separate_and_return_only_aggregates(
    ops_client: tuple[TestClient, Session],
) -> None:
    """把 Ops 路由挂到公网业务应用或返回用户明细时应失败。"""
    client, session = ops_client
    user = User(
        id=uuid4(),
        email_hash="不可逆摘要",
        masked_email="s***@example.com",
    )
    session.add(user)
    session.commit()
    session.add(
        SyncMutation(
            user_id=user.id,
            mutation_id=uuid4(),
            entity_type="app_settings",
            entity_id=uuid4(),
            outcome="conflict",
            result_payload={"status": "conflict"},
        ),
    )
    session.add(
        AccountDeletionRequest(
            user_id=user.id,
            status="pending",
            requested_at=utc_now(),
            purge_after=utc_now() + timedelta(days=7),
        ),
    )
    AiUsageRecorder(session).record(
        provider="deepseek",
        model="deepseek-chat",
        capability="chat",
        prompt_contract_version="chat-v2",
        input_tokens=10,
        output_tokens=5,
        prompt_cache_hit_tokens=6,
        prompt_cache_miss_tokens=4,
        latency_ms=80,
        result_code="generated",
        request_id="req-ops-001",
    )
    session.commit()

    public_app = create_app()
    with TestClient(public_app) as public_client:
        assert public_client.get("/ops/v1/summary").status_code == 404

    for path in (
        "/ops/v1/summary",
        "/ops/v1/sync-health",
        "/ops/v1/ai-usage",
        "/ops/v1/deletion-jobs",
    ):
        response = client.get(path)
        assert response.status_code == 200
        serialized = response.text.lower()
        assert "example.com" not in serialized
        assert "email_hash" not in serialized
        assert '"prompt":' not in serialized
        assert '"payload":' not in serialized
        assert "api_key" not in serialized

    summary = client.get("/ops/v1/summary").json()
    assert summary == {
        "users_total": 1,
        "synced_users_total": 1,
        "sync_conflicts_24h": 1,
        "ai_requests_24h": 1,
        "deletion_pending": 1,
    }
    usage = client.get("/ops/v1/ai-usage").json()
    assert usage["groups"][0] == {
        "provider": "deepseek",
        "model": "deepseek-chat",
        "capability": "chat",
        "prompt_contract_version": "chat-v2",
        "result_code": "generated",
        "requests": 1,
        "input_tokens": 10,
        "output_tokens": 5,
        "prompt_cache_hit_tokens": 6,
        "prompt_cache_miss_tokens": 4,
        "average_latency_ms": 80,
    }
