from collections.abc import Generator
from dataclasses import dataclass, field
from uuid import UUID

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, select
from sqlalchemy.engine import Engine
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool

from app.api.auth import get_email_provider, get_sms_provider
from app.core.config import Settings, get_settings
from app.core.errors import ApiError
from app.db.base import Base
from app.db.session import get_session
from app.main import create_app
from app.models import EmailChallenge, User
from app.services.auth_service import AuthService, ConsentInput, DeviceInput

CURRENT_AGREEMENT_VERSION = "internal-test-2026-07-13.1"


@dataclass
class FakeSmsProvider:
    """测试中保存验证码，生产代码不记录或返回验证码。"""

    messages: list[tuple[str, str, int]] = field(default_factory=list)

    def send_verification_code(
        self,
        phone: str,
        code: str,
        expires_in_seconds: int,
    ) -> None:
        self.messages.append((phone, code, expires_in_seconds))


@dataclass
class FakeEmailProvider:
    """测试中保存验证码，生产代码不记录或返回验证码。"""

    messages: list[tuple[str, str, int]] = field(default_factory=list)

    def send_verification_code(
        self,
        email: str,
        code: str,
        expires_in_seconds: int,
    ) -> None:
        self.messages.append((email, code, expires_in_seconds))


@pytest.fixture
def auth_client() -> Generator[tuple[TestClient, FakeSmsProvider], None, None]:
    engine = create_engine(
        "sqlite+pysqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(engine)
    session_factory = sessionmaker(bind=engine)
    provider = FakeSmsProvider()
    app = create_app()

    def get_test_session() -> Generator[Session, None, None]:
        with session_factory() as session:
            yield session

    app.dependency_overrides[get_session] = get_test_session
    app.dependency_overrides[get_sms_provider] = lambda: provider

    with TestClient(app) as client:
        yield client, provider

    app.dependency_overrides.clear()
    Base.metadata.drop_all(engine)
    engine.dispose()


@pytest.fixture
def email_auth_client() -> Generator[
    tuple[TestClient, FakeEmailProvider, Engine],
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
    app = create_app()

    def get_test_session() -> Generator[Session, None, None]:
        with session_factory() as session:
            yield session

    app.dependency_overrides[get_session] = get_test_session
    app.dependency_overrides[get_email_provider] = lambda: provider

    with TestClient(app) as client:
        yield client, provider, engine

    app.dependency_overrides.clear()
    Base.metadata.drop_all(engine)
    engine.dispose()


def _device_payload() -> dict[str, str]:
    return {
        "installation_id": "019f4220-5ce2-7082-b418-5d087d24a4a9",
        "platform": "web",
        "device_name": "测试浏览器",
    }


def _request_challenge(
    client: TestClient,
    phone: str = "13800138000",
) -> dict[str, object]:
    response = client.post("/v1/auth/sms-challenges", json={"phone": phone})

    assert response.status_code == 201
    payload = response.json()
    assert "code" not in payload
    assert payload["expires_in_seconds"] == 300
    return payload


def _request_email_challenge(
    client: TestClient,
    email: str = "runner@example.com",
) -> dict[str, object]:
    response = client.post("/v1/auth/email-challenges", json={"email": email})

    assert response.status_code == 201
    payload = response.json()
    assert "code" not in payload
    assert "email" not in payload
    assert payload["expires_in_seconds"] == 300
    return payload


def test_first_login_requires_consent_and_returns_a_session(
    auth_client: tuple[TestClient, FakeSmsProvider],
) -> None:
    client, provider = auth_client
    challenge = _request_challenge(client)
    _, code, _ = provider.messages[-1]

    missing_consent = client.post(
        "/v1/auth/sessions",
        json={
            "phone": "13800138000",
            "challenge_id": challenge["challenge_id"],
            "code": code,
            "device": _device_payload(),
        },
    )

    assert missing_consent.status_code == 422
    assert missing_consent.json()["code"] == "consent_required"

    response = client.post(
        "/v1/auth/sessions",
        json={
            "phone": "13800138000",
            "challenge_id": challenge["challenge_id"],
            "code": code,
            "device": _device_payload(),
            "consents": {
                "terms_version": CURRENT_AGREEMENT_VERSION,
                "privacy_version": CURRENT_AGREEMENT_VERSION,
            },
        },
    )

    assert response.status_code == 201
    tokens = response.json()
    assert tokens["token_type"] == "bearer"
    assert tokens["refresh_token"]

    current_user = client.get(
        "/v1/auth/me",
        headers={"Authorization": f"Bearer {tokens['access_token']}"},
    )

    assert current_user.status_code == 200
    assert current_user.json()["account_type"] == "phone"
    assert current_user.json()["masked_email"] is None
    assert current_user.json()["phone_last4"] == "8000"
    assert current_user.json()["has_required_consents"] is True


def test_email_login_normalizes_identity_and_returns_masked_account(
    email_auth_client: tuple[TestClient, FakeEmailProvider, Engine],
) -> None:
    client, provider, engine = email_auth_client
    challenge = _request_email_challenge(client, email=" Runner@Example.COM ")
    delivered_email, code, _ = provider.messages[-1]

    assert delivered_email == "runner@example.com"
    assert code == "246810"

    missing_consent = client.post(
        "/v1/auth/sessions",
        json={
            "email": "runner@example.com",
            "challenge_id": challenge["challenge_id"],
            "code": code,
            "device": _device_payload(),
        },
    )
    assert missing_consent.status_code == 422
    assert missing_consent.json()["code"] == "consent_required"

    response = client.post(
        "/v1/auth/sessions",
        json={
            "email": "RUNNER@example.com",
            "challenge_id": challenge["challenge_id"],
            "code": code,
            "device": _device_payload(),
            "consents": {
                "terms_version": CURRENT_AGREEMENT_VERSION,
                "privacy_version": CURRENT_AGREEMENT_VERSION,
            },
        },
    )

    assert response.status_code == 201
    current_user = client.get(
        "/v1/auth/me",
        headers={"Authorization": f"Bearer {response.json()['access_token']}"},
    )
    assert current_user.status_code == 200
    assert current_user.json()["account_type"] == "email"
    assert current_user.json()["masked_email"] == "r***@example.com"
    assert current_user.json()["phone_last4"] is None

    with Session(engine) as session:
        user = session.scalar(select(User))
        email_challenge = session.scalar(select(EmailChallenge))
        assert user is not None
        assert user.email_hash != "runner@example.com"
        assert user.masked_email != "runner@example.com"
        assert email_challenge is not None
        assert not hasattr(email_challenge, "email")


def test_session_requires_exactly_one_login_identity(
    email_auth_client: tuple[TestClient, FakeEmailProvider, Engine],
) -> None:
    client, _, _ = email_auth_client
    base_payload = {
        "challenge_id": "019f4220-5ce2-7082-b418-5d087d24a4a9",
        "code": "246810",
        "device": _device_payload(),
    }

    missing = client.post("/v1/auth/sessions", json=base_payload)
    duplicated = client.post(
        "/v1/auth/sessions",
        json={
            **base_payload,
            "email": "runner@example.com",
            "phone": "13800138000",
        },
    )

    assert missing.status_code == 422
    assert duplicated.status_code == 422
    assert "邮箱和手机号必须且只能填写一个" in missing.text
    assert "邮箱和手机号必须且只能填写一个" in duplicated.text


def test_email_challenge_rate_limit_is_enforced(
    email_auth_client: tuple[TestClient, FakeEmailProvider, Engine],
) -> None:
    client, provider, _ = email_auth_client

    for _ in range(3):
        _request_email_challenge(client, email="rate@example.com")

    blocked = client.post(
        "/v1/auth/email-challenges",
        json={"email": "rate@example.com"},
    )

    assert blocked.status_code == 429
    assert blocked.json()["code"] == "email_rate_limited"
    assert len(provider.messages) == 3


def test_email_challenge_stays_locked_after_max_attempts(
    email_auth_client: tuple[TestClient, FakeEmailProvider, Engine],
) -> None:
    client, provider, _ = email_auth_client
    challenge = _request_email_challenge(client, email="locked@example.com")
    _, correct_code, _ = provider.messages[-1]
    payload = {
        "email": "locked@example.com",
        "challenge_id": challenge["challenge_id"],
        "device": _device_payload(),
        "consents": {
            "terms_version": CURRENT_AGREEMENT_VERSION,
            "privacy_version": CURRENT_AGREEMENT_VERSION,
        },
    }

    for attempt in range(5):
        response = client.post(
            "/v1/auth/sessions",
            json={**payload, "code": "000000"},
        )
        expected_code = (
            "email_challenge_locked" if attempt == 4 else "email_code_invalid"
        )
        assert response.status_code == 401
        assert response.json()["code"] == expected_code

    retry_with_correct_code = client.post(
        "/v1/auth/sessions",
        json={**payload, "code": correct_code},
    )

    assert retry_with_correct_code.status_code == 401
    assert retry_with_correct_code.json()["code"] == "email_challenge_locked"


def test_consumed_email_challenge_cannot_create_another_session(
    email_auth_client: tuple[TestClient, FakeEmailProvider, Engine],
) -> None:
    client, provider, _ = email_auth_client
    challenge = _request_email_challenge(client, email="single-use@example.com")
    _, code, _ = provider.messages[-1]
    payload = {
        "email": "single-use@example.com",
        "challenge_id": challenge["challenge_id"],
        "code": code,
        "device": _device_payload(),
        "consents": {
            "terms_version": CURRENT_AGREEMENT_VERSION,
            "privacy_version": CURRENT_AGREEMENT_VERSION,
        },
    }

    first_session = client.post("/v1/auth/sessions", json=payload)
    replay = client.post("/v1/auth/sessions", json=payload)

    assert first_session.status_code == 201
    assert replay.status_code == 401
    assert replay.json()["code"] == "email_challenge_invalid"


def test_sms_challenge_stays_locked_after_max_attempts(
    auth_client: tuple[TestClient, FakeSmsProvider],
) -> None:
    client, provider = auth_client
    challenge = _request_challenge(client, phone="13500135000")
    _, correct_code, _ = provider.messages[-1]
    payload = {
        "phone": "13500135000",
        "challenge_id": challenge["challenge_id"],
        "device": _device_payload(),
        "consents": {
            "terms_version": CURRENT_AGREEMENT_VERSION,
            "privacy_version": CURRENT_AGREEMENT_VERSION,
        },
    }

    for attempt in range(5):
        response = client.post(
            "/v1/auth/sessions",
            json={**payload, "code": "000000"},
        )
        expected_code = "sms_challenge_locked" if attempt == 4 else "sms_code_invalid"
        assert response.status_code == 401
        assert response.json()["code"] == expected_code

    retry_with_correct_code = client.post(
        "/v1/auth/sessions",
        json={**payload, "code": correct_code},
    )

    assert retry_with_correct_code.status_code == 401
    assert retry_with_correct_code.json()["code"] == "sms_challenge_locked"


def test_refresh_rotation_rejects_replayed_token(
    auth_client: tuple[TestClient, FakeSmsProvider],
) -> None:
    client, provider = auth_client
    challenge = _request_challenge(client)
    _, code, _ = provider.messages[-1]
    session = client.post(
        "/v1/auth/sessions",
        json={
            "phone": "13800138000",
            "challenge_id": challenge["challenge_id"],
            "code": code,
            "device": _device_payload(),
            "consents": {
                "terms_version": CURRENT_AGREEMENT_VERSION,
                "privacy_version": CURRENT_AGREEMENT_VERSION,
            },
        },
    )
    original_refresh_token = session.json()["refresh_token"]

    rotated = client.post(
        "/v1/auth/tokens/refresh",
        json={"refresh_token": original_refresh_token},
    )

    assert rotated.status_code == 200
    rotated_refresh_token = rotated.json()["refresh_token"]
    assert rotated_refresh_token != original_refresh_token

    replay = client.post(
        "/v1/auth/tokens/refresh",
        json={"refresh_token": original_refresh_token},
    )

    assert replay.status_code == 401
    assert replay.json()["code"] == "refresh_token_replayed"

    family_revoked = client.post(
        "/v1/auth/tokens/refresh",
        json={"refresh_token": rotated_refresh_token},
    )

    assert family_revoked.status_code == 401


def test_refresh_and_logout_do_not_depend_on_delivery_providers(
    auth_client: tuple[TestClient, FakeSmsProvider],
) -> None:
    client, provider = auth_client
    challenge = _request_challenge(client)
    _, code, _ = provider.messages[-1]
    login = client.post(
        "/v1/auth/sessions",
        json={
            "phone": "13800138000",
            "challenge_id": challenge["challenge_id"],
            "code": code,
            "device": _device_payload(),
            "consents": {
                "terms_version": CURRENT_AGREEMENT_VERSION,
                "privacy_version": CURRENT_AGREEMENT_VERSION,
            },
        },
    )
    disabled_settings = Settings(
        sms_provider="disabled",
        email_provider="disabled",
    )
    client.app.dependency_overrides[get_settings] = lambda: disabled_settings  # type: ignore[attr-defined]

    refreshed = client.post(
        "/v1/auth/tokens/refresh",
        json={"refresh_token": login.json()["refresh_token"]},
    )
    assert refreshed.status_code == 200

    logout = client.delete(
        "/v1/auth/sessions/current",
        headers={
            "Authorization": f"Bearer {refreshed.json()['access_token']}",
        },
    )
    assert logout.status_code == 204


def test_sms_challenge_rate_limit_is_enforced(
    auth_client: tuple[TestClient, FakeSmsProvider],
) -> None:
    client, provider = auth_client

    for _ in range(3):
        _request_challenge(client, phone="13900139000")

    blocked = client.post(
        "/v1/auth/sms-challenges",
        json={"phone": "13900139000"},
    )

    assert blocked.status_code == 429
    assert blocked.json()["code"] == "sms_rate_limited"
    assert len(provider.messages) == 3


def test_logout_revokes_the_current_access_token(
    auth_client: tuple[TestClient, FakeSmsProvider],
) -> None:
    client, provider = auth_client
    challenge = _request_challenge(client)
    _, code, _ = provider.messages[-1]
    session = client.post(
        "/v1/auth/sessions",
        json={
            "phone": "13800138000",
            "challenge_id": challenge["challenge_id"],
            "code": code,
            "device": _device_payload(),
            "consents": {
                "terms_version": CURRENT_AGREEMENT_VERSION,
                "privacy_version": CURRENT_AGREEMENT_VERSION,
            },
        },
    )
    access_token = session.json()["access_token"]
    headers = {"Authorization": f"Bearer {access_token}"}

    logout = client.delete("/v1/auth/sessions/current", headers=headers)

    assert logout.status_code == 204
    current_user = client.get("/v1/auth/me", headers=headers)
    assert current_user.status_code == 401
    assert current_user.json()["code"] == "access_token_invalid"


def test_production_configuration_rejects_example_keys() -> None:
    with pytest.raises(ValueError, match="生产环境必须配置安全密钥"):
        Settings(app_env="production")


def test_disabled_sms_rejects_before_using_the_database() -> None:
    app = create_app()
    disabled_settings = Settings(sms_provider="disabled")

    def get_unused_session() -> Generator[Session, None, None]:
        yield object()  # type: ignore[misc]

    app.dependency_overrides[get_session] = get_unused_session
    app.dependency_overrides[get_settings] = lambda: disabled_settings
    with TestClient(app) as client:
        response = client.post(
            "/v1/auth/sms-challenges",
            json={"phone": "13800138000"},
        )

    app.dependency_overrides.clear()
    assert response.status_code == 503
    assert response.json()["code"] == "sms_not_configured"


def test_disabled_email_rejects_before_using_the_database() -> None:
    app = create_app()
    disabled_settings = Settings(email_provider="disabled")

    def get_unused_session() -> Generator[Session, None, None]:
        yield object()  # type: ignore[misc]

    app.dependency_overrides[get_session] = get_unused_session
    app.dependency_overrides[get_settings] = lambda: disabled_settings
    with TestClient(app) as client:
        response = client.post(
            "/v1/auth/email-challenges",
            json={"email": "runner@example.com"},
        )

    app.dependency_overrides.clear()
    assert response.status_code == 503
    assert response.json()["code"] == "email_not_configured"


def test_public_config_only_returns_non_sensitive_login_configuration() -> None:
    client = TestClient(create_app())

    response = client.get("/v1/auth/public-config")

    assert response.status_code == 200
    assert response.json() == {
        "terms_version": CURRENT_AGREEMENT_VERSION,
        "privacy_version": CURRENT_AGREEMENT_VERSION,
        "sms_mode": "development",
        "email_mode": "development",
    }
    assert "code" not in response.text
    assert "key" not in response.text.lower()


def test_development_sms_uses_fixed_test_code_without_returning_it(
    auth_client: tuple[TestClient, FakeSmsProvider],
) -> None:
    client, provider = auth_client

    payload = _request_challenge(client, phone="13700137000")

    assert provider.messages[-1][1] == "246810"
    assert "246810" not in str(payload)


def test_outdated_agreement_version_is_rejected(
    auth_client: tuple[TestClient, FakeSmsProvider],
) -> None:
    client, provider = auth_client
    challenge = _request_challenge(client, phone="13600136000")
    _, code, _ = provider.messages[-1]

    response = client.post(
        "/v1/auth/sessions",
        json={
            "phone": "13600136000",
            "challenge_id": challenge["challenge_id"],
            "code": code,
            "device": _device_payload(),
            "consents": {
                "terms_version": "outdated",
                "privacy_version": "outdated",
            },
        },
    )

    assert response.status_code == 422
    assert response.json()["code"] == "consent_version_invalid"


def test_production_rejects_development_sms_and_internal_agreements() -> None:
    secure_values = {
        "jwt_signing_key": "a" * 48,
        "phone_hash_key": "b" * 48,
        "email_hash_key": "e" * 48,
        "sms_code_signing_key": "c" * 48,
        "email_code_signing_key": "f" * 48,
        "refresh_token_signing_key": "d" * 48,
        "minimax_api_key": "test-only-minimax-key",
        "deepseek_api_key": "test-only-deepseek-key",
    }
    with pytest.raises(ValueError, match="禁止使用 development 短信模式"):
        Settings(app_env="production", **secure_values)

    with pytest.raises(ValueError, match="禁止使用内部测试协议版本"):
        Settings(
            app_env="production",
            sms_provider="disabled",
            email_provider="smtp",
            smtp_host="smtp.example.com",
            smtp_username="test-user",
            smtp_password="test-password",
            smtp_from_email="noreply@example.com",
            **secure_values,
        )


def test_production_rejects_development_email_and_incomplete_smtp() -> None:
    secure_values = {
        "jwt_signing_key": "a" * 48,
        "phone_hash_key": "b" * 48,
        "email_hash_key": "e" * 48,
        "sms_code_signing_key": "c" * 48,
        "email_code_signing_key": "f" * 48,
        "refresh_token_signing_key": "d" * 48,
        "minimax_api_key": "test-only-minimax-key",
        "deepseek_api_key": "test-only-deepseek-key",
        "terms_version": "2026-07-16.1",
        "privacy_version": "2026-07-16.1",
        "sms_provider": "disabled",
    }
    with pytest.raises(ValueError, match="禁止使用 development 邮件模式"):
        Settings(app_env="production", **secure_values)

    with pytest.raises(ValueError, match="SMTP 邮件配置不完整"):
        Settings(
            app_env="production",
            email_provider="smtp",
            **secure_values,
        )


def test_existing_account_must_accept_the_new_current_agreement() -> None:
    engine = create_engine(
        "sqlite+pysqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(engine)
    provider = FakeSmsProvider()
    settings = Settings()
    device = DeviceInput(
        installation_id=UUID(_device_payload()["installation_id"]),
        platform="web",
        device_name="测试浏览器",
    )
    with Session(engine) as session:
        service = AuthService(session, settings, provider)
        first_challenge = service.request_sms_challenge("13800138000")
        service.create_session_from_sms(
            "13800138000",
            first_challenge,
            provider.messages[-1][1],
            device,
            ConsentInput(
                terms_version=settings.terms_version,
                privacy_version=settings.privacy_version,
            ),
        )

        settings.terms_version = "internal-test-2026-07-14.1"
        settings.privacy_version = "internal-test-2026-07-14.1"
        second_challenge = service.request_sms_challenge("13800138000")
        with pytest.raises(ApiError) as captured:
            service.create_session_from_sms(
                "13800138000",
                second_challenge,
                provider.messages[-1][1],
                device,
                None,
            )

        assert captured.value.code == "consent_required"
        tokens = service.create_session_from_sms(
            "13800138000",
            second_challenge,
            provider.messages[-1][1],
            device,
            ConsentInput(
                terms_version=settings.terms_version,
                privacy_version=settings.privacy_version,
            ),
        )
        assert tokens.access_token

    Base.metadata.drop_all(engine)
    engine.dispose()
