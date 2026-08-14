from __future__ import annotations

from collections.abc import Generator
from dataclasses import dataclass, field
from datetime import timedelta
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, select
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool

from app.api.auth import get_email_provider
from app.core.config import Settings, get_settings
from app.core.security import utc_now
from app.db.base import Base
from app.db.session import get_session
from app.main import create_app
from app.models import (
    AccountDeletionReceipt,
    AccountDeletionRequest,
    User,
)
from app.services.account_lifecycle import AccountLifecycleService

CURRENT_AGREEMENT_VERSION = "internal-test-2026-07-13.1"
EMAIL = "delete-me@example.com"


@dataclass
class FakeEmailProvider:
    """测试邮箱发送记录，不进入生产日志。"""

    messages: list[tuple[str, str, int]] = field(default_factory=list)

    def send_verification_code(
        self,
        email: str,
        code: str,
        expires_in_seconds: int,
    ) -> None:
        self.messages.append((email, code, expires_in_seconds))


AccountClientFixture = tuple[
    TestClient,
    FakeEmailProvider,
    sessionmaker[Session],
    Settings,
]


@pytest.fixture
def account_client() -> Generator[AccountClientFixture, None, None]:
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
        yield client, provider, session_factory, settings

    app.dependency_overrides.clear()
    Base.metadata.drop_all(engine)
    engine.dispose()


def _login(
    client: TestClient,
    provider: FakeEmailProvider,
    *,
    email: str = EMAIL,
) -> dict[str, str]:
    challenge = client.post(
        "/v1/auth/email-challenges",
        json={"email": email},
    )
    assert challenge.status_code == 201
    _, code, _ = provider.messages[-1]
    response = client.post(
        "/v1/auth/sessions",
        json={
            "email": email,
            "challenge_id": challenge.json()["challenge_id"],
            "code": code,
            "device": {
                "installation_id": str(uuid4()),
                "platform": "ios",
                "device_name": "删除测试设备",
            },
            "consents": {
                "terms_version": CURRENT_AGREEMENT_VERSION,
                "privacy_version": CURRENT_AGREEMENT_VERSION,
            },
        },
    )
    assert response.status_code == 201
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


def _request_deletion_challenge(
    client: TestClient,
    provider: FakeEmailProvider,
    headers: dict[str, str],
) -> tuple[str, str]:
    response = client.post(
        "/v1/account/deletion-challenges",
        headers=headers,
        json={"email": EMAIL},
    )
    assert response.status_code == 201
    _, code, _ = provider.messages[-1]
    return response.json()["challenge_id"], code


def _preference_mutation() -> dict[str, object]:
    return {
        "mutations": [
            {
                "mutation_id": str(uuid4()),
                "entity_type": "training_preferences",
                "entity_id": str(uuid4()),
                "operation": "upsert",
                "base_version": None,
                "payload": {
                    "goal": "完成内测",
                    "sport_types": ["running"],
                    "experience_level": "beginner",
                    "weekly_availability": [2, 4],
                    "equipment": [],
                },
            },
        ],
    }


def test_account_export_contains_only_current_users_safe_cloud_projection(
    account_client: AccountClientFixture,
) -> None:
    """导出若混入邮箱明文或敏感训练字段，应由此测试阻止。"""
    client, provider, _, _ = account_client
    headers = _login(client, provider)
    synced = client.post(
        "/v1/sync/mutations",
        headers=headers,
        json=_preference_mutation(),
    )
    assert synced.status_code == 200

    response = client.get("/v1/account/export", headers=headers)

    assert response.status_code == 200
    assert response.headers["content-disposition"].startswith("attachment;")
    payload = response.json()
    assert payload["account"]["account_type"] == "email"
    assert payload["sync"]["entities"]["training_preferences"][0]["payload"][
        "goal"
    ] == "完成内测"
    serialized = response.text.lower()
    assert EMAIL not in serialized
    for forbidden in (
        "weight",
        "height",
        "healthkit",
        "pain",
        "rpe",
        "heart_rate",
        "route",
        "image",
        "voice",
    ):
        assert forbidden not in serialized


def test_deletion_request_revokes_all_sessions_and_stops_sync(
    account_client: AccountClientFixture,
) -> None:
    """少撤销一个会话或允许待删除账号继续同步都会造成数据风险。"""
    client, provider, _, _ = account_client
    first_headers = _login(client, provider)
    second_headers = _login(client, provider)
    challenge_id, code = _request_deletion_challenge(
        client,
        provider,
        first_headers,
    )

    requested = client.post(
        "/v1/account/deletion-requests",
        headers=first_headers,
        json={
            "email": EMAIL,
            "challenge_id": challenge_id,
            "code": code,
        },
    )

    assert requested.status_code == 201
    assert requested.json()["status"] == "pending"
    assert requested.json()["grace_period_days"] == 7
    assert client.get("/v1/auth/me", headers=first_headers).status_code == 401
    assert client.get("/v1/auth/me", headers=second_headers).status_code == 401

    relogged_headers = _login(client, provider)
    status_response = client.get(
        "/v1/account/deletion-status",
        headers=relogged_headers,
    )
    assert status_response.status_code == 200
    assert status_response.json()["status"] == "pending"

    blocked_sync = client.post(
        "/v1/sync/mutations",
        headers=relogged_headers,
        json=_preference_mutation(),
    )
    assert blocked_sync.status_code == 423
    assert blocked_sync.json()["code"] == "account_deletion_pending"


def test_deletion_can_be_cancelled_during_grace_period(
    account_client: AccountClientFixture,
) -> None:
    """取消后若删除任务或同步锁仍生效，用户将无法恢复账号。"""
    client, provider, _, _ = account_client
    headers = _login(client, provider)
    challenge_id, code = _request_deletion_challenge(client, provider, headers)
    requested = client.post(
        "/v1/account/deletion-requests",
        headers=headers,
        json={
            "email": EMAIL,
            "challenge_id": challenge_id,
            "code": code,
        },
    )
    assert requested.status_code == 201

    relogged_headers = _login(client, provider)
    cancelled = client.post(
        "/v1/account/deletion-cancellations",
        headers=relogged_headers,
    )
    assert cancelled.status_code == 200
    assert cancelled.json()["status"] == "cancelled"

    status_response = client.get(
        "/v1/account/deletion-status",
        headers=relogged_headers,
    )
    assert status_response.json()["status"] == "cancelled"
    resumed_sync = client.post(
        "/v1/sync/mutations",
        headers=relogged_headers,
        json=_preference_mutation(),
    )
    assert resumed_sync.status_code == 200


def test_due_deletion_purges_identity_and_keeps_anonymous_receipt(
    account_client: AccountClientFixture,
) -> None:
    """到期清理不能留下用户标识，且必须保留不含 user_id 的匿名回执。"""
    client, provider, session_factory, settings = account_client
    headers = _login(client, provider)
    challenge_id, code = _request_deletion_challenge(client, provider, headers)
    requested = client.post(
        "/v1/account/deletion-requests",
        headers=headers,
        json={
            "email": EMAIL,
            "challenge_id": challenge_id,
            "code": code,
        },
    )
    request_id = requested.json()["request_id"]

    with session_factory() as session:
        deletion_request = session.scalar(select(AccountDeletionRequest))
        assert deletion_request is not None
        deletion_request.purge_after = utc_now() - timedelta(seconds=1)
        session.commit()

        purged = AccountLifecycleService(
            session,
            settings,
        ).purge_due_deletions()

        receipt = session.scalar(select(AccountDeletionReceipt))
        assert purged == 1
        assert session.scalar(select(User)) is None
        assert receipt is not None
        assert str(receipt.deletion_request_id) == request_id
        assert not hasattr(receipt, "user_id")
