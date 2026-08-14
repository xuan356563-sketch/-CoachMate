from __future__ import annotations

from collections.abc import Generator
from dataclasses import dataclass, field
from datetime import timedelta
from uuid import UUID, uuid4

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool

from app.api.auth import get_email_provider
from app.api.billing import get_apple_transaction_verifier
from app.core.config import Settings, get_settings
from app.core.security import utc_now
from app.db.base import Base
from app.db.session import get_session
from app.main import create_app
from app.services.subscription_billing import (
    VerifiedAppleNotification,
    VerifiedAppleTransaction,
)

CURRENT_AGREEMENT_VERSION = "internal-test-2026-07-13.1"


@dataclass
class FakeEmailProvider:
    messages: list[tuple[str, str, int]] = field(default_factory=list)

    def send_verification_code(
        self,
        email: str,
        code: str,
        expires_in_seconds: int,
    ) -> None:
        self.messages.append((email, code, expires_in_seconds))


class FakeAppleVerifier:
    app_account_token: UUID | None = None

    def verify_transaction(
        self,
        verification_data: str,
    ) -> VerifiedAppleTransaction:
        return VerifiedAppleTransaction(
            transaction_id="transaction-1",
            original_transaction_id="original-1",
            product_id="com.zhilian.trainmate.membership.monthly",
            app_account_token=self.app_account_token
            or UUID("11111111-1111-4111-8111-111111111111"),
            environment="sandbox",
            purchased_at=utc_now(),
            expires_at=utc_now() + timedelta(days=7),
            revoked_at=None,
            is_trial=True,
        )

    def verify_notification(
        self,
        signed_payload: str,
    ) -> VerifiedAppleNotification:
        return VerifiedAppleNotification(
            notification_uuid="notification-1",
            notification_type="DID_RENEW",
            subtype=None,
            transaction=self.verify_transaction("notification"),
        )


@pytest.fixture
def billing_client() -> Generator[
    tuple[TestClient, FakeEmailProvider, FakeAppleVerifier],
    None,
    None,
]:
    engine = create_engine(
        "sqlite+pysqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(engine)
    session_factory = sessionmaker(bind=engine)
    provider = FakeEmailProvider()
    verifier = FakeAppleVerifier()
    settings = Settings(
        ios_subscription_enabled=True,
        paid_plan_generation_gate_enabled=True,
        apple_subscription_environment="sandbox",
    )
    app = create_app()

    def get_test_session() -> Generator[Session, None, None]:
        with session_factory() as session:
            yield session

    app.dependency_overrides[get_session] = get_test_session
    app.dependency_overrides[get_email_provider] = lambda: provider
    app.dependency_overrides[get_settings] = lambda: settings
    app.dependency_overrides[get_apple_transaction_verifier] = lambda: verifier

    with TestClient(app) as client:
        yield client, provider, verifier

    app.dependency_overrides.clear()
    Base.metadata.drop_all(engine)
    engine.dispose()


def _login(
    client: TestClient,
    provider: FakeEmailProvider,
) -> tuple[dict[str, str], str]:
    challenge = client.post(
        "/v1/auth/email-challenges",
        json={"email": "billing@example.com"},
    )
    _, code, _ = provider.messages[-1]
    response = client.post(
        "/v1/auth/sessions",
        json={
            "email": "billing@example.com",
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
    return (
        {"Authorization": f"Bearer {response.json()['access_token']}"},
        response.json()["access_token"],
    )


def test_verified_trial_unlocks_plan_generation(
    billing_client: tuple[TestClient, FakeEmailProvider, FakeAppleVerifier],
) -> None:
    client, provider, verifier = billing_client
    headers, _ = _login(client, provider)
    user = client.get("/v1/auth/me", headers=headers).json()
    verifier.app_account_token = UUID(user["user_id"])

    empty = client.get("/v1/billing/entitlement", headers=headers)
    assert empty.status_code == 200
    assert empty.json()["status"] == "none"

    verified = client.post(
        "/v1/billing/apple/transactions/verify",
        headers=headers,
        json={
            "request_id": str(uuid4()),
            "verification_data": "signed-transaction",
            "app_account_token": user["user_id"],
        },
    )

    assert verified.status_code == 200
    assert verified.json()["status"] == "trial"
    assert verified.json()["can_generate_plan"] is True
    assert verified.json()["product_id"] == (
        "com.zhilian.trainmate.membership.monthly"
    )


def test_transaction_rejects_mismatched_app_account_token(
    billing_client: tuple[TestClient, FakeEmailProvider, FakeAppleVerifier],
) -> None:
    client, provider, verifier = billing_client
    headers, _ = _login(client, provider)
    user = client.get("/v1/auth/me", headers=headers).json()
    verifier.app_account_token = UUID(user["user_id"])

    response = client.post(
        "/v1/billing/apple/transactions/verify",
        headers=headers,
        json={
            "request_id": str(uuid4()),
            "verification_data": "signed-transaction",
            "app_account_token": str(uuid4()),
        },
    )

    assert response.status_code == 422
    assert response.json()["code"] == "apple_transaction_account_mismatch"


def test_apple_notification_is_idempotent(
    billing_client: tuple[TestClient, FakeEmailProvider, FakeAppleVerifier],
) -> None:
    client, provider, verifier = billing_client
    headers, _ = _login(client, provider)
    user = client.get("/v1/auth/me", headers=headers).json()
    verifier.app_account_token = UUID(user["user_id"])

    first = client.post(
        "/v1/billing/apple/notifications",
        json={"signedPayload": "signed-notification"},
    )
    second = client.post(
        "/v1/billing/apple/notifications",
        json={"signedPayload": "signed-notification"},
    )

    assert first.status_code == 204
    assert second.status_code == 204
