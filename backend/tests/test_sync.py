from __future__ import annotations

from collections.abc import Generator
from dataclasses import dataclass, field
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool

from app.api.auth import get_email_provider
from app.core.config import Settings, get_settings
from app.db.base import Base
from app.db.session import get_session
from app.main import create_app

CURRENT_AGREEMENT_VERSION = "internal-test-2026-07-13.1"


@dataclass
class FakeEmailProvider:
    """只在测试进程内保存验证码。"""

    messages: list[tuple[str, str, int]] = field(default_factory=list)

    def send_verification_code(
        self,
        email: str,
        code: str,
        expires_in_seconds: int,
    ) -> None:
        self.messages.append((email, code, expires_in_seconds))


@pytest.fixture
def sync_client() -> Generator[tuple[TestClient, FakeEmailProvider], None, None]:
    engine = create_engine(
        "sqlite+pysqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(engine)
    session_factory = sessionmaker(bind=engine)
    provider = FakeEmailProvider()
    settings = Settings(sync_enabled=True)
    app = create_app()

    def get_test_session() -> Generator[Session, None, None]:
        with session_factory() as session:
            yield session

    app.dependency_overrides[get_session] = get_test_session
    app.dependency_overrides[get_email_provider] = lambda: provider
    app.dependency_overrides[get_settings] = lambda: settings

    with TestClient(app) as client:
        yield client, provider

    app.dependency_overrides.clear()
    Base.metadata.drop_all(engine)
    engine.dispose()


def _login(
    client: TestClient,
    provider: FakeEmailProvider,
    *,
    email: str,
) -> dict[str, str]:
    challenge = client.post(
        "/v1/auth/email-challenges",
        json={"email": email},
    )
    assert challenge.status_code == 201
    _, code, _ = provider.messages[-1]
    session = client.post(
        "/v1/auth/sessions",
        json={
            "email": email,
            "challenge_id": challenge.json()["challenge_id"],
            "code": code,
            "device": {
                "installation_id": str(uuid4()),
                "platform": "ios",
                "device_name": "测试设备",
            },
            "consents": {
                "terms_version": CURRENT_AGREEMENT_VERSION,
                "privacy_version": CURRENT_AGREEMENT_VERSION,
            },
        },
    )
    assert session.status_code == 201
    return {"Authorization": f"Bearer {session.json()['access_token']}"}


def _preferences_mutation(
    *,
    mutation_id: str | None = None,
    entity_id: str | None = None,
    base_version: int | None = None,
) -> dict[str, object]:
    return {
        "mutation_id": mutation_id or str(uuid4()),
        "entity_type": "training_preferences",
        "entity_id": entity_id or str(uuid4()),
        "operation": "upsert",
        "base_version": base_version,
        "payload": {
            "goal": "提升综合体能",
            "sport_types": ["running", "strength"],
            "experience_level": "intermediate",
            "weekly_availability": [1, 3, 6],
            "equipment": ["dumbbell"],
        },
    }


def test_sync_rejects_sensitive_or_undeclared_fields_with_stable_error(
    sync_client: tuple[TestClient, FakeEmailProvider],
) -> None:
    """删除字段白名单检查会使测试错误地接受体重数据。"""
    client, provider = sync_client
    headers = _login(client, provider, email="privacy@example.com")
    mutation = _preferences_mutation()
    mutation["payload"]["weight_kg"] = 72

    response = client.post(
        "/v1/sync/mutations",
        headers=headers,
        json={"mutations": [mutation]},
    )

    assert response.status_code == 422
    assert response.json() == {
        "code": "sync_payload_invalid",
        "detail": "同步请求包含未声明或不允许的字段。",
    }

    request_with_extra = client.post(
        "/v1/sync/mutations",
        headers=headers,
        json={"mutations": [_preferences_mutation()], "debug": True},
    )
    assert request_with_extra.status_code == 422
    assert request_with_extra.json()["code"] == "sync_payload_invalid"


def test_sync_mutation_is_idempotent_and_visible_in_snapshot(
    sync_client: tuple[TestClient, FakeEmailProvider],
) -> None:
    """删除幂等记录会让同一 mutation_id 产生第二条增量记录。"""
    client, provider = sync_client
    headers = _login(client, provider, email="idempotent@example.com")
    mutation = _preferences_mutation()

    first = client.post(
        "/v1/sync/mutations",
        headers=headers,
        json={"mutations": [mutation]},
    )
    second = client.post(
        "/v1/sync/mutations",
        headers=headers,
        json={"mutations": [mutation]},
    )

    assert first.status_code == 200
    assert second.status_code == 200
    assert first.json() == second.json()
    assert first.json()["results"][0]["status"] == "applied"
    assert first.json()["results"][0]["version"] == 1

    snapshot = client.get("/v1/sync/snapshot", headers=headers)
    assert snapshot.status_code == 200
    assert snapshot.json()["cursor"] == 1
    assert snapshot.json()["entities"]["training_preferences"] == [
        {
            "entity_id": mutation["entity_id"],
            "version": 1,
            "payload": mutation["payload"],
        },
    ]

    changes = client.get("/v1/sync/changes?after=0&limit=100", headers=headers)
    assert changes.status_code == 200
    assert len(changes.json()["changes"]) == 1


def test_versioned_sync_returns_conflict_without_overwriting_cloud_state(
    sync_client: tuple[TestClient, FakeEmailProvider],
) -> None:
    """移除 base_version 检查会覆盖另一设备刚写入的偏好。"""
    client, provider = sync_client
    headers = _login(client, provider, email="conflict@example.com")
    entity_id = str(uuid4())
    original = _preferences_mutation(entity_id=entity_id)
    assert (
        client.post(
            "/v1/sync/mutations",
            headers=headers,
            json={"mutations": [original]},
        ).status_code
        == 200
    )
    stale = _preferences_mutation(entity_id=entity_id, base_version=0)
    stale["payload"]["goal"] = "覆盖云端"

    response = client.post(
        "/v1/sync/mutations",
        headers=headers,
        json={"mutations": [stale]},
    )

    assert response.status_code == 200
    result = response.json()["results"][0]
    assert result["status"] == "conflict"
    assert result["version"] == 1
    assert result["cloud_payload"]["goal"] == "提升综合体能"

    snapshot = client.get("/v1/sync/snapshot", headers=headers).json()
    assert (
        snapshot["entities"]["training_preferences"][0]["payload"]["goal"]
        == "提升综合体能"
    )


def test_changes_are_cursor_paginated_and_account_isolated(
    sync_client: tuple[TestClient, FakeEmailProvider],
) -> None:
    """移除 user_id 过滤会向另一个账号泄露同步摘要。"""
    client, provider = sync_client
    first_headers = _login(client, provider, email="first@example.com")
    second_headers = _login(client, provider, email="second@example.com")

    entity_id = str(uuid4())
    first_mutation = _preferences_mutation(entity_id=entity_id)
    second_mutation = _preferences_mutation(
        entity_id=entity_id,
        base_version=1,
    )
    second_mutation["payload"]["goal"] = "继续提升综合体能"
    for mutation in (first_mutation, second_mutation):
        response = client.post(
            "/v1/sync/mutations",
            headers=first_headers,
            json={"mutations": [mutation]},
        )
        assert response.status_code == 200

    hidden = client.post(
        "/v1/sync/mutations",
        headers=second_headers,
        json={"mutations": [_preferences_mutation()]},
    )
    assert hidden.status_code == 200

    first_page = client.get(
        "/v1/sync/changes?after=0&limit=1",
        headers=first_headers,
    )
    assert first_page.status_code == 200
    assert len(first_page.json()["changes"]) == 1
    assert first_page.json()["has_more"] is True
    next_cursor = first_page.json()["next_cursor"]

    second_page = client.get(
        f"/v1/sync/changes?after={next_cursor}&limit=1",
        headers=first_headers,
    )
    assert second_page.status_code == 200
    assert len(second_page.json()["changes"]) == 1
    assert second_page.json()["has_more"] is False
    assert all(
        change["entity_id"] != hidden.json()["results"][0]["entity_id"]
        for change in first_page.json()["changes"] + second_page.json()["changes"]
    )


def test_sync_requires_login_and_feature_flag(
    sync_client: tuple[TestClient, FakeEmailProvider],
) -> None:
    """移除认证或功能开关会让未授权客户端写入云端。"""
    client, provider = sync_client
    anonymous = client.post(
        "/v1/sync/mutations",
        json={"mutations": [_preferences_mutation()]},
    )
    assert anonymous.status_code == 401

    headers = _login(client, provider, email="disabled@example.com")
    app = client.app
    app.dependency_overrides[get_settings] = lambda: Settings(sync_enabled=False)
    disabled = client.post(
        "/v1/sync/mutations",
        headers=headers,
        json={"mutations": [_preferences_mutation()]},
    )
    assert disabled.status_code == 503
    assert disabled.json()["code"] == "sync_disabled"
