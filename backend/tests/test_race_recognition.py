import asyncio
from collections.abc import Generator
from dataclasses import dataclass
from uuid import UUID

import httpx
import pytest
import redis
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool

from app.api.auth import get_sms_provider
from app.api.races import (
    get_race_recognition_rate_limiter,
    get_race_recognition_service,
)
from app.core.config import Settings
from app.core.errors import ApiError
from app.db.base import Base
from app.db.session import get_session
from app.main import create_app
from app.services.race_recognition import (
    HttpMiniMaxClient,
    MiniMaxModelOutput,
    RaceRecognitionService,
    RecognizedRaceFields,
)
from app.services.race_recognition_rate_limit import RaceRecognitionRateLimiter

_PNG = b"\x89PNG\r\n\x1a\n" + b"test-image"


@dataclass
class FakeSmsProvider:
    code: str = ""

    def send_verification_code(
        self,
        phone: str,
        code: str,
        expires_in_seconds: int,
    ) -> None:
        del phone, expires_in_seconds
        self.code = code


class FakeMiniMaxClient:
    def __init__(self, output: MiniMaxModelOutput) -> None:
        self.output = output
        self.image_data_url = ""

    async def recognize(self, image_data_url: str) -> MiniMaxModelOutput:
        self.image_data_url = image_data_url
        return self.output


class FakeRateLimiter:
    def __init__(self) -> None:
        self.checked = 0

    def check(self, _user_id) -> None:
        self.checked += 1


@pytest.fixture
def race_client() -> Generator[tuple[TestClient, FakeMiniMaxClient], None, None]:
    engine = create_engine(
        "sqlite+pysqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(engine)
    session_factory = sessionmaker(bind=engine)
    sms_provider = FakeSmsProvider()
    minimax_client = FakeMiniMaxClient(
        MiniMaxModelOutput(
            fields=RecognizedRaceFields(
                name="示例马拉松",
                type="marathon",
                race_date="2026-11-29",
                course_info="全程马拉松，城市公路赛道",
            ),
        ),
    )
    settings = Settings()
    service = RaceRecognitionService(settings, minimax_client)
    limiter = FakeRateLimiter()
    app = create_app()

    def get_test_session() -> Generator[Session, None, None]:
        with session_factory() as session:
            yield session

    app.dependency_overrides[get_session] = get_test_session
    app.dependency_overrides[get_sms_provider] = lambda: sms_provider
    app.dependency_overrides[get_race_recognition_service] = lambda: service
    app.dependency_overrides[get_race_recognition_rate_limiter] = lambda: limiter

    with TestClient(app) as client:
        challenge = client.post(
            "/v1/auth/sms-challenges",
            json={"phone": "13800138000"},
        ).json()
        session_response = client.post(
            "/v1/auth/sessions",
            json={
                "phone": "13800138000",
                "challenge_id": challenge["challenge_id"],
                "code": sms_provider.code,
                "device": {
                    "installation_id": "019f4220-5ce2-7082-b418-5d087d24a4a9",
                    "platform": "web",
                },
                "consents": {
                    "terms_version": settings.terms_version,
                    "privacy_version": settings.privacy_version,
                },
            },
        )
        client.headers["Authorization"] = (
            f"Bearer {session_response.json()['access_token']}"
        )
        yield client, minimax_client

    app.dependency_overrides.clear()
    Base.metadata.drop_all(engine)
    engine.dispose()


def test_image_recognition_requires_login() -> None:
    client = TestClient(create_app())

    response = client.post(
        "/v1/races/image-recognition",
        files={"image": ("race.png", _PNG, "image/png")},
    )

    assert response.status_code == 401
    assert response.json()["code"] == "access_token_required"


def test_image_recognition_returns_only_normalized_fields(
    race_client: tuple[TestClient, FakeMiniMaxClient],
) -> None:
    client, minimax_client = race_client

    response = client.post(
        "/v1/races/image-recognition",
        files={"image": ("race.png", _PNG, "image/png")},
    )

    assert response.status_code == 200
    assert response.json() == {
        "provider": "minimax",
        "model": "MiniMax-M3",
        "fields": {
            "name": "示例马拉松",
            "type": "marathon",
            "race_date": "2026-11-29",
            "target_result": None,
            "course_info": "全程马拉松，城市公路赛道",
        },
        "normalized_text": (
            "赛事：示例马拉松\n类型：marathon\n日期：2026-11-29\n"
            "赛道：全程马拉松，城市公路赛道"
        ),
        "matched_field_count": 4,
        "warnings": [],
    }
    assert minimax_client.image_data_url.startswith("data:image/png;base64,")
    assert "test-image" not in response.text


def test_partial_recognition_keeps_missing_fields_empty() -> None:
    fake_client = FakeMiniMaxClient(
        MiniMaxModelOutput(
            fields=RecognizedRaceFields(type="trail_running"),
        ),
    )
    service = RaceRecognitionService(Settings(), fake_client)

    result = asyncio.run(service.recognize(_PNG))

    assert result.matched_field_count == 1
    assert result.normalized_text == "类型：trail_running"
    assert "未能确认赛事名称，请手动补充" in result.warnings
    assert "未能确认比赛日期，请手动补充" in result.warnings


@pytest.mark.parametrize(
    ("image", "expected_code"),
    [
        (b"", "image_empty"),
        (b"HEIC-image", "image_type_unsupported"),
    ],
)
def test_invalid_image_is_rejected(image: bytes, expected_code: str) -> None:
    service = RaceRecognitionService(
        Settings(),
        FakeMiniMaxClient(MiniMaxModelOutput(fields=RecognizedRaceFields())),
    )

    with pytest.raises(ApiError) as captured:
        asyncio.run(service.recognize(image))

    assert captured.value.code == expected_code


def test_image_over_ten_megabytes_is_rejected_before_calling_model() -> None:
    fake_client = FakeMiniMaxClient(
        MiniMaxModelOutput(fields=RecognizedRaceFields()),
    )
    service = RaceRecognitionService(
        Settings(race_image_max_bytes=1024),
        fake_client,
    )

    with pytest.raises(ApiError) as captured:
        asyncio.run(service.recognize(_PNG + b"x" * 1024))

    assert captured.value.code == "image_too_large"
    assert fake_client.image_data_url == ""


def test_sensitive_model_result_is_not_returned() -> None:
    service = RaceRecognitionService(
        Settings(),
        FakeMiniMaxClient(
            MiniMaxModelOutput(
                fields=RecognizedRaceFields(),
                sensitive_content=True,
            ),
        ),
    )

    with pytest.raises(ApiError) as captured:
        asyncio.run(service.recognize(_PNG))

    assert captured.value.code == "image_content_unsupported"


def test_minimax_connection_5xx_is_retried_once() -> None:
    call_count = 0

    async def handler(request: httpx.Request) -> httpx.Response:
        nonlocal call_count
        call_count += 1
        if call_count == 1:
            return httpx.Response(503, request=request)
        return httpx.Response(
            200,
            request=request,
            json={
                "choices": [
                    {
                        "message": {
                            "content": (
                                '{"fields":{"name":"重试成功","type":null,'
                                '"race_date":null,"target_result":null,'
                                '"course_info":null},"warnings":[],'
                                '"sensitive_content":false}'
                            ),
                        },
                    },
                ],
            },
        )

    client = HttpMiniMaxClient(
        Settings(minimax_api_key="test-key"),
        transport=httpx.MockTransport(handler),
    )

    result = asyncio.run(client.recognize("data:image/png;base64,dGVzdA=="))

    assert result.fields.name == "重试成功"
    assert call_count == 2


def test_invalid_minimax_json_is_converted_to_stable_error() -> None:
    async def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            200,
            request=request,
            json={"choices": [{"message": {"content": "不是 JSON"}}]},
        )

    client = HttpMiniMaxClient(
        Settings(minimax_api_key="test-key"),
        transport=httpx.MockTransport(handler),
    )

    with pytest.raises(ApiError) as captured:
        asyncio.run(client.recognize("data:image/png;base64,dGVzdA=="))

    assert captured.value.code == "minimax_invalid_output"


def test_missing_minimax_key_is_rejected_before_network_request() -> None:
    client = HttpMiniMaxClient(Settings(minimax_api_key=None))

    with pytest.raises(ApiError) as captured:
        asyncio.run(client.recognize("data:image/png;base64,dGVzdA=="))

    assert captured.value.code == "minimax_not_configured"


def test_minimax_timeout_returns_chinese_timeout_error() -> None:
    async def handler(request: httpx.Request) -> httpx.Response:
        raise httpx.ReadTimeout("测试超时", request=request)

    client = HttpMiniMaxClient(
        Settings(minimax_api_key="test-key"),
        transport=httpx.MockTransport(handler),
    )

    with pytest.raises(ApiError) as captured:
        asyncio.run(client.recognize("data:image/png;base64,dGVzdA=="))

    assert captured.value.code == "minimax_timeout"
    assert "超时" in captured.value.detail


def test_development_rate_limiter_falls_back_to_memory() -> None:
    class BrokenRedis:
        def pipeline(self, transaction: bool = True):
            del transaction
            raise redis.ConnectionError("测试 Redis 不可用")

    limiter = RaceRecognitionRateLimiter(
        Settings(race_recognition_limit=1),
    )
    limiter._redis = BrokenRedis()  # type: ignore[assignment]
    user_id = UUID("019f4220-5ce2-7082-b418-5d087d24a4a9")

    limiter.check(user_id)
    with pytest.raises(ApiError) as captured:
        limiter.check(user_id)

    assert captured.value.code == "race_recognition_rate_limited"


def test_production_rate_limiter_fails_closed_when_redis_is_unavailable() -> None:
    class BrokenRedis:
        def pipeline(self, transaction: bool = True):
            del transaction
            raise redis.ConnectionError("测试 Redis 不可用")

    settings = Settings()
    settings.app_env = "production"
    limiter = RaceRecognitionRateLimiter(settings)
    limiter._redis = BrokenRedis()  # type: ignore[assignment]

    with pytest.raises(ApiError) as captured:
        limiter.check(UUID("019f4220-5ce2-7082-b418-5d087d24a4a9"))

    assert captured.value.code == "race_recognition_rate_limit_unavailable"
