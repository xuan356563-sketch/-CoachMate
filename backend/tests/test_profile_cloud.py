from __future__ import annotations

from collections.abc import Generator
from dataclasses import dataclass, field
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, text
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool

from app.api.auth import get_email_provider
from app.core.config import Settings, get_settings
from app.db.base import Base
from app.db.session import get_session
from app.main import create_app

CURRENT_AGREEMENT_VERSION = "internal-test-2026-07-13.1"
TEST_PROFILE_KEY = "MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWY="


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
def profile_client() -> Generator[
    tuple[TestClient, FakeEmailProvider, sessionmaker[Session]],
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
    settings = Settings(
        sync_enabled=True,
        health_profile_cloud_enabled=True,
        profile_encryption_key=TEST_PROFILE_KEY,
        profile_encryption_key_version="test-v1",
    )
    app = create_app()

    def get_test_session() -> Generator[Session, None, None]:
        with session_factory() as session:
            yield session

    app.dependency_overrides[get_session] = get_test_session
    app.dependency_overrides[get_email_provider] = lambda: provider
    app.dependency_overrides[get_settings] = lambda: settings

    with TestClient(app) as client:
        yield client, provider, session_factory

    app.dependency_overrides.clear()
    Base.metadata.drop_all(engine)
    engine.dispose()


def _login(
    client: TestClient,
    provider: FakeEmailProvider,
    *,
    email: str = "profile@example.com",
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
                "device_name": "测试设备",
            },
            "consents": {
                "terms_version": CURRENT_AGREEMENT_VERSION,
                "privacy_version": CURRENT_AGREEMENT_VERSION,
            },
        },
    )
    assert response.status_code == 201
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


def _profile_mutation(*, include_health: bool) -> dict[str, object]:
    return {
        "mutation_id": str(uuid4()),
        "entity_type": "user_profile",
        "entity_id": str(uuid4()),
        "operation": "upsert",
        "base_version": None,
        "payload": {
            "schema_version": 1,
            "nickname": "小智",
            "gender": "male",
            "declared_age": 32,
            "height_cm": 175 if include_health else None,
            "weight_kg": 72 if include_health else None,
            "worker_profile_type": "sedentary_office",
            "work_schedule_type": "regular_office",
            "training_goal": "fat_loss",
            "main_sports": ["running", "strength"],
            "training_experience_level": "beginner",
            "training_environment": "gym",
            "weekly_training_days": 3,
            "daily_available_minutes": 45,
            "core_self_report": "seconds_20_45",
            "aerobic_talk_test": "minutes_10_20",
            "cardio_recovery": "minutes_1_3",
            "injuries": (
                [
                    {
                        "body_region": "right_knee",
                        "state": "occasional_discomfort",
                        "limiting_activity": "squat",
                        "confirmed_note": "右膝偶有不适",
                    }
                ]
                if include_health
                else []
            ),
            "health_fields_included": include_health,
        },
    }


def test_health_profile_requires_separate_consent(
    profile_client: tuple[TestClient, FakeEmailProvider, sessionmaker[Session]],
) -> None:
    client, provider, _ = profile_client
    headers = _login(client, provider)

    response = client.post(
        "/v1/sync/mutations",
        headers=headers,
        json={"mutations": [_profile_mutation(include_health=True)]},
    )

    assert response.status_code == 403
    assert response.json()["code"] == "health_profile_cloud_consent_required"


def test_confirmed_profile_is_encrypted_and_revoke_scrubs_health_fields(
    profile_client: tuple[TestClient, FakeEmailProvider, sessionmaker[Session]],
) -> None:
    client, provider, session_factory = profile_client
    headers = _login(client, provider)
    consent = client.put(
        "/v1/account/consents/health-profile-cloud",
        headers=headers,
        json={
            "granted": True,
            "document_version": "health-profile-cloud-2026-07-31.1",
        },
    )
    assert consent.status_code == 200
    mutation = _profile_mutation(include_health=True)

    saved = client.post(
        "/v1/sync/mutations",
        headers=headers,
        json={"mutations": [mutation]},
    )

    assert saved.status_code == 200
    snapshot = client.get("/v1/sync/snapshot", headers=headers).json()
    profile = snapshot["entities"]["user_profile"][0]["payload"]
    assert profile["height_cm"] == 175
    assert profile["injuries"][0]["body_region"] == "right_knee"

    with session_factory() as session:
        row = session.execute(
            text(
                "SELECT ciphertext, nonce, key_version "
                "FROM cloud_user_profiles"
            )
        ).one()
        stored = bytes(row.ciphertext)
        assert b"right_knee" not in stored
        assert b"72" not in stored
        assert row.nonce
        assert row.key_version == "test-v1"
        change_payload = session.execute(
            text(
                "SELECT payload FROM sync_changes "
                "WHERE entity_type = 'user_profile'"
            )
        ).scalar_one()
        assert "right_knee" not in str(change_payload)
        assert "小智" not in str(change_payload)

    revoked = client.put(
        "/v1/account/consents/health-profile-cloud",
        headers=headers,
        json={
            "granted": False,
            "document_version": "health-profile-cloud-2026-07-31.1",
        },
    )
    assert revoked.status_code == 200
    snapshot = client.get("/v1/sync/snapshot", headers=headers).json()
    scrubbed = snapshot["entities"]["user_profile"][0]["payload"]
    assert scrubbed["height_cm"] is None
    assert scrubbed["weight_kg"] is None
    assert scrubbed["injuries"] == []
    assert scrubbed["health_fields_included"] is False


def test_profile_payload_rejects_raw_transcript_and_unknown_fields(
    profile_client: tuple[TestClient, FakeEmailProvider, sessionmaker[Session]],
) -> None:
    client, provider, _ = profile_client
    headers = _login(client, provider)
    mutation = _profile_mutation(include_health=False)
    mutation["payload"]["raw_transcript"] = "不应上传的原始口述"

    response = client.post(
        "/v1/sync/mutations",
        headers=headers,
        json={"mutations": [mutation]},
    )

    assert response.status_code == 422
    assert response.json()["code"] == "sync_payload_invalid"
