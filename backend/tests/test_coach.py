from __future__ import annotations

from collections.abc import Generator
from dataclasses import dataclass, field
from datetime import timedelta
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient
from pydantic import ValidationError
from sqlalchemy import create_engine, text
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool

from app.api.auth import get_email_provider
from app.core.config import Settings, get_settings
from app.core.security import utc_now
from app.db.base import Base
from app.db.session import get_session
from app.main import create_app
from app.services.coach.contracts import CoachProjectionPutRequest, canonical_digest

CURRENT_AGREEMENT_VERSION = "internal-test-2026-07-13.1"
COACH_CONSENT_VERSION = "coach-cloud-projection-2026-08-12.1"
COACH_CONTRACT_HASH = (
    "8970f0e215ddc5b54709eb5febeef2ca506b823e4095f54be9b9d31956e078e0"
)
TEST_PROFILE_KEY = "MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWY="


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


@pytest.fixture
def coach_client() -> Generator[
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
        coach_cloud_projection_enabled=True,
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
    email: str = "coach@example.com",
) -> dict[str, str]:
    challenge = client.post(
        "/v1/auth/email-challenges", json={"email": email}
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
                "device_name": "Coach 测试设备",
            },
            "consents": {
                "terms_version": CURRENT_AGREEMENT_VERSION,
                "privacy_version": CURRENT_AGREEMENT_VERSION,
            },
        },
    )
    assert response.status_code == 201
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


def _grant(client: TestClient, headers: dict[str, str]) -> None:
    response = client.put(
        "/v1/account/consents/coach-cloud-projection",
        headers=headers,
        json={"granted": True, "document_version": COACH_CONSENT_VERSION},
    )
    assert response.status_code == 200


def _projection(*, severe: bool = False, base_version: int | None = None) -> dict:
    now = utc_now()
    memories: list[dict] = []
    return {
        "base_version": base_version,
        "state": {
            "snapshot_id": "snapshot-1",
            "source_digest": "a" * 64,
            "snapshot_digest": "b" * 64,
            "contract_version": 1,
            "contract_hash": COACH_CONTRACT_HASH,
            "rule_set_version": "coach-rules-1.0.0",
            "generated_at": now.isoformat(),
            "valid_until": (now + timedelta(hours=5)).isoformat(),
            "local_date": now.date().isoformat(),
            "planned_action_id": "follow-existing-plan",
            "planned_duration_minutes": 45,
            "available_minutes": 30,
            "recovery_band": "green",
            "completed_sessions_7d": 3,
            "missed_sessions_7d": 0,
            "safety_flags": ["severe_pain"] if severe else [],
            "quality_codes": ["body_data_available"],
            "missing_fields": [],
        },
        "memories": memories,
        "memory_set_digest": canonical_digest(memories),
    }


def _evaluation(**overrides: object) -> dict:
    value: dict[str, object] = {
        "turn_id": f"turn-{uuid4()}",
        "snapshot_id": "snapshot-1",
        "snapshot_digest": "b" * 64,
        "memory_set_digest": canonical_digest([]),
        "intent": "today_training",
        "emotion": "neutral",
        "contract_version": 1,
        "contract_hash": COACH_CONTRACT_HASH,
        "rule_set_version": "coach-rules-1.0.0",
        "requested_action_ids": ["follow-existing-plan"],
    }
    value.update(overrides)
    return value


def test_non_empty_memory_digest_uses_transmitted_json() -> None:
    projection = _projection()
    now = utc_now()
    memories = [
        {
            "memory_id": "memory-1",
            "category": "preference",
            "version": 1,
            "display_text": "喜欢先做五分钟热身",
            "confidence_bps": 9000,
            "valid_until": (now + timedelta(days=180)).isoformat(),
            "until_revoked": False,
            "may_mention": True,
            "user_confirmed": True,
            "sync_allowed": True,
            "source_digests": ["c" * 64],
        }
    ]
    projection["memories"] = memories
    projection["memory_set_digest"] = canonical_digest(memories)

    parsed = CoachProjectionPutRequest.model_validate(projection)
    assert parsed.memories[0].display_text == "喜欢先做五分钟热身"

    memories[0]["display_text"] = "摘要后被篡改"
    with pytest.raises(ValidationError, match="记忆集合摘要不一致"):
        CoachProjectionPutRequest.model_validate(projection)


def test_projection_requires_separate_consent(
    coach_client: tuple[TestClient, FakeEmailProvider, sessionmaker[Session]],
) -> None:
    client, provider, _ = coach_client
    headers = _login(client, provider)

    response = client.put(
        "/v1/coach/projections/current",
        headers=headers,
        json=_projection(),
    )

    assert response.status_code == 403
    assert response.json()["code"] == "coach_cloud_projection_consent_required"


def test_projection_is_encrypted_and_evaluation_reads_server_projection(
    coach_client: tuple[TestClient, FakeEmailProvider, sessionmaker[Session]],
) -> None:
    client, provider, session_factory = coach_client
    headers = _login(client, provider)
    _grant(client, headers)
    saved = client.put(
        "/v1/coach/projections/current",
        headers=headers,
        json=_projection(),
    )
    assert saved.status_code == 200

    with session_factory() as session:
        row = session.execute(
            text("SELECT ciphertext, nonce FROM coach_state_projections")
        ).one()
        assert b"follow-existing-plan" not in bytes(row.ciphertext)
        assert row.nonce

    evaluated = client.post(
        "/v1/coach/evaluations",
        headers=headers,
        json=_evaluation(),
    )
    assert evaluated.status_code == 200
    body = evaluated.json()
    assert body["allowed"] == [
        {
            "action_id": "follow-existing-plan",
            "intensity": "moderate",
            "duration_minutes": 30,
            "requires_confirmation": False,
            "route": "/plans",
        }
    ]
    with session_factory() as session:
        audit = session.execute(
            text(
                "SELECT reason_codes, request_digest, decision_digest "
                "FROM coach_rule_audits"
            )
        ).one()
        assert "existing_plan_available" in str(audit.reason_codes)
        assert len(audit.request_digest) == 64
        assert len(audit.decision_digest) == 64


def test_evaluation_rejects_client_snapshot_and_digest_mismatch(
    coach_client: tuple[TestClient, FakeEmailProvider, sessionmaker[Session]],
) -> None:
    client, provider, _ = coach_client
    headers = _login(client, provider)
    _grant(client, headers)
    assert client.put(
        "/v1/coach/projections/current", headers=headers, json=_projection()
    ).status_code == 200

    raw_snapshot = _evaluation(snapshot={"pain": 0}, profile={"name": "不允许"})
    rejected = client.post(
        "/v1/coach/evaluations", headers=headers, json=raw_snapshot
    )
    assert rejected.status_code == 422
    assert rejected.json()["code"] == "coach_request_invalid"

    raw_content = _projection()
    raw_content["raw_health_samples"] = [{"heart_rate": 180}]
    raw_content["conversation_text"] = "不允许上传的完整对话"
    rejected_projection = client.put(
        "/v1/coach/projections/current",
        headers=headers,
        json=raw_content,
    )
    assert rejected_projection.status_code == 422
    assert rejected_projection.json()["code"] == "coach_request_invalid"

    mismatch = client.post(
        "/v1/coach/evaluations",
        headers=headers,
        json=_evaluation(snapshot_digest="c" * 64),
    )
    assert mismatch.status_code == 409
    assert mismatch.json()["code"] == "coach_snapshot_mismatch"


def test_projection_is_strictly_scoped_to_logged_in_user(
    coach_client: tuple[TestClient, FakeEmailProvider, sessionmaker[Session]],
) -> None:
    client, provider, _ = coach_client
    first_headers = _login(client, provider, email="coach-a@example.com")
    _grant(client, first_headers)
    assert client.put(
        "/v1/coach/projections/current",
        headers=first_headers,
        json=_projection(),
    ).status_code == 200

    second_headers = _login(client, provider, email="coach-b@example.com")
    _grant(client, second_headers)
    response = client.post(
        "/v1/coach/evaluations",
        headers=second_headers,
        json=_evaluation(),
    )

    assert response.status_code == 409
    assert response.json()["code"] == "coach_projection_missing"


def test_server_safety_projection_blocks_requested_training_and_revoke_deletes(
    coach_client: tuple[TestClient, FakeEmailProvider, sessionmaker[Session]],
) -> None:
    client, provider, session_factory = coach_client
    headers = _login(client, provider)
    _grant(client, headers)
    assert client.put(
        "/v1/coach/projections/current",
        headers=headers,
        json=_projection(severe=True),
    ).status_code == 200

    response = client.post(
        "/v1/coach/evaluations", headers=headers, json=_evaluation()
    )
    assert response.status_code == 200
    assert response.json()["allowed"] == []
    assert response.json()["risk_level"] == "critical"
    assert response.json()["reason_codes"] == ["pain_redline"]

    revoked = client.put(
        "/v1/account/consents/coach-cloud-projection",
        headers=headers,
        json={"granted": False, "document_version": COACH_CONSENT_VERSION},
    )
    assert revoked.status_code == 200
    with session_factory() as session:
        assert session.execute(
            text("SELECT COUNT(*) FROM coach_state_projections")
        ).scalar_one() == 0
        assert session.execute(
            text("SELECT COUNT(*) FROM coach_memory_projections")
        ).scalar_one() == 0
