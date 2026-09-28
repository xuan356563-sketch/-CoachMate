import asyncio
import struct
import zlib
from collections.abc import Generator
from dataclasses import dataclass
from io import BytesIO
from uuid import UUID

import httpx
import pytest
from fastapi.testclient import TestClient
from PIL import Image
from sqlalchemy import create_engine, select
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool

from app.api.ai import get_ai_artifact_service, get_ai_rate_limiter
from app.api.auth import get_sms_provider
from app.core.config import Settings
from app.core.errors import ApiError
from app.db.base import Base
from app.db.session import get_session
from app.main import create_app
from app.models.ai import AiArtifact, AiGenerationJob
from app.services.ai_generation import (
    AiArtifactService,
    AiTextGenerationRequest,
    GeneratedAiArtifact,
    HttpDeepSeekClient,
)


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


class FakeTextClient:
    def __init__(self) -> None:
        self.calls = 0
        self.requests: list[AiTextGenerationRequest] = []

    async def generate(
        self,
        request: AiTextGenerationRequest,
    ) -> GeneratedAiArtifact:
        self.calls += 1
        self.requests.append(request)
        if request.capability == "trainer":
            payload = {
                "cycle_label": "稳态建立周",
                "weekly_structure": "每周 3 次可执行训练。",
                "workout_cards": [
                    {
                        "title": "低冲击力量",
                        "duration_minutes": 35,
                        "intensity": "轻松",
                        "focus": ["动作质量", "核心稳定"],
                        "safety_note": "疼痛出现时立即停止相关动作。",
                    },
                ],
                "safety_notes": ["不以疼痛换取训练进度。"],
            }
            artifact_type = "trainer_plan_v1"
        else:
            payload = {
                "readiness_score": 68,
                "recommended_action": "完成轻松训练后安排恢复。",
                "factors": ["睡眠充足", "无明显疼痛"],
                "today_tasks": ["完成热身", "训练后补水"],
                "red_flags": [],
                "safety_note": "准备度下降时切换到恢复版。",
            }
            artifact_type = "recovery_dashboard_v1"
        return GeneratedAiArtifact(
            capability=request.capability,
            artifact_type=artifact_type,
            schema_version=1,
            payload=payload,
            warnings=[],
            provider="deepseek",
            model="fake-deepseek",
        )


class FakeMotionClient:
    def __init__(self) -> None:
        self.calls = 0
        self.image = b""
        self.rule_id = ""

    async def generate(
        self,
        *,
        image: bytes,
        rule_id: str,
        local_pose_summary: str,
    ) -> GeneratedAiArtifact:
        del local_pose_summary
        self.calls += 1
        self.image = image
        self.rule_id = rule_id
        return GeneratedAiArtifact(
            capability="motion",
            artifact_type="motion_score_v1",
            schema_version=1,
            payload={
                "score": 74,
                "risk_level": "medium",
                "confidence": 0.8,
                "detected_errors": ["膝盖轨迹不稳定"],
                "corrections": ["降低深度后保持膝盖对齐脚尖"],
                "replacements": ["箱式深蹲"],
                "safety_note": "出现疼痛时停止负重深蹲。",
            },
            warnings=[],
            provider="minimax",
            model="fake-minimax",
        )


class FakeRateLimiter:
    def __init__(self) -> None:
        self.checked = 0

    def check(self, _user_id: UUID) -> None:
        self.checked += 1


@pytest.fixture
def ai_client() -> Generator[
    tuple[TestClient, FakeTextClient, FakeMotionClient, Session],
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
    service_session = Session(engine)
    settings = Settings()
    sms_provider = FakeSmsProvider()
    text_client = FakeTextClient()
    motion_client = FakeMotionClient()
    service = AiArtifactService(service_session, settings, text_client, motion_client)
    limiter = FakeRateLimiter()
    app = create_app()

    def get_test_session() -> Generator[Session, None, None]:
        with session_factory() as session:
            yield session

    app.dependency_overrides[get_session] = get_test_session
    app.dependency_overrides[get_sms_provider] = lambda: sms_provider
    app.dependency_overrides[get_ai_artifact_service] = lambda: service
    app.dependency_overrides[get_ai_rate_limiter] = lambda: limiter

    with TestClient(app) as client:
        challenge = client.post(
            "/v1/auth/sms-challenges",
            json={"phone": "13800138000"},
        ).json()
        login = client.post(
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
            f"Bearer {login.json()['access_token']}"
        )
        yield client, text_client, motion_client, service_session

    app.dependency_overrides.clear()
    service_session.close()
    Base.metadata.drop_all(engine)
    engine.dispose()


def _trainer_request(prompt: str = "下周只在晚上有 30 分钟") -> dict[str, object]:
    return {
        "capability": "trainer",
        "prompt": prompt,
        "context": {
            "goal": "完成 10 公里比赛",
            "sports": ["跑步", "力量"],
            "available_minutes": 30,
            "scheduled_minutes": 30,
            "scheduled_period": "晚上",
        },
    }


def test_ai_generation_requires_login() -> None:
    client = TestClient(create_app())

    response = client.post("/v1/ai/generations", json=_trainer_request())

    assert response.status_code == 401
    assert response.json()["code"] == "access_token_required"


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("readiness_score", 68),
        ("daily_decision", "降低强度"),
        ("pain_level", 4),
        ("health_summary", {"resting_heart_rate": 80}),
    ],
)
def test_text_generation_rejects_health_derived_context(
    ai_client: tuple[TestClient, FakeTextClient, FakeMotionClient, Session],
    field: str,
    value: object,
) -> None:
    client, text_client, _, _ = ai_client
    request = _trainer_request()
    context = request["context"]
    assert isinstance(context, dict)
    context[field] = value

    response = client.post("/v1/ai/generations", json=request)

    assert response.status_code == 422
    assert text_client.calls == 0


def test_text_artifact_is_cached_and_only_persists_validated_result(
    ai_client: tuple[TestClient, FakeTextClient, FakeMotionClient, Session],
) -> None:
    client, text_client, _, service_session = ai_client
    prompt = "下周只在晚上有 30 分钟"

    first = client.post("/v1/ai/generations", json=_trainer_request(prompt))
    second = client.post("/v1/ai/generations", json=_trainer_request(prompt))

    assert first.status_code == 201
    assert second.status_code == 201
    assert first.json()["id"] == second.json()["id"]
    assert text_client.calls == 1
    assert first.json()["artifact_type"] == "trainer_plan_v1"
    assert first.json()["payload"]["workout_cards"][0]["title"] == "低冲击力量"

    job = service_session.execute(select(AiGenerationJob)).scalar_one()
    artifact = service_session.execute(select(AiArtifact)).scalar_one()
    assert job.state == "completed"
    assert job.error_code is None
    assert prompt not in str(job.__dict__)
    assert prompt not in str(artifact.__dict__)

    listed = client.get("/v1/ai/artifacts")
    assert listed.status_code == 200
    assert len(listed.json()["artifacts"]) == 1

    accepted = client.post(
        f"/v1/ai/artifacts/{first.json()['id']}/decision",
        json={"decision": "accepted"},
    )
    assert accepted.status_code == 200
    assert accepted.json()["decision_status"] == "accepted"

    deleted = client.delete(f"/v1/ai/artifacts/{first.json()['id']}")
    assert deleted.status_code == 204
    assert client.get("/v1/ai/artifacts").json()["artifacts"] == []


def test_motion_image_is_sanitized_in_memory_before_client_call(
    ai_client: tuple[TestClient, FakeTextClient, FakeMotionClient, Session],
) -> None:
    client, _, motion_client, service_session = ai_client
    raw = BytesIO()
    exif = Image.Exif()
    exif[270] = "private motion photo"
    Image.new("RGB", (20, 20), color="white").save(raw, format="JPEG", exif=exif)
    raw_bytes = raw.getvalue()
    assert b"Exif" in raw_bytes

    response = client.post(
        "/v1/ai/motion-analysis",
        files={"image": ("motion.jpg", raw_bytes, "image/jpeg")},
        data={"rule_id": "squat", "local_pose_summary": "本地评分 70"},
    )

    assert response.status_code == 201
    assert response.json()["artifact_type"] == "motion_score_v1"
    assert motion_client.calls == 1
    assert motion_client.rule_id == "squat"
    assert b"Exif" not in motion_client.image
    assert b"private motion photo" not in motion_client.image
    stored = service_session.execute(select(AiArtifact)).scalar_one()
    assert "private motion photo" not in str(stored.payload)
    assert "image" not in stored.payload


def test_motion_image_rejects_oversized_dimensions_before_pixel_decode(
    ai_client: tuple[TestClient, FakeTextClient, FakeMotionClient, Session],
) -> None:
    client, _, motion_client, service_session = ai_client

    def png_chunk(kind: bytes, data: bytes) -> bytes:
        chunk = kind + data
        return (
            struct.pack(">I", len(data))
            + chunk
            + struct.pack(">I", zlib.crc32(chunk) & 0xFFFFFFFF)
        )

    header = struct.pack(">IIBBBBB", 6000, 5000, 8, 2, 0, 0, 0)
    oversized_png = (
        b"\x89PNG\r\n\x1a\n"
        + png_chunk(b"IHDR", header)
        + png_chunk(b"IDAT", b"")
        + png_chunk(b"IEND", b"")
    )

    response = client.post(
        "/v1/ai/motion-analysis",
        files={"image": ("oversized.png", oversized_png, "image/png")},
        data={"rule_id": "squat", "local_pose_summary": "本地评分 70"},
    )

    assert response.status_code == 413
    assert response.json()["code"] == "image_dimensions_invalid"
    assert motion_client.calls == 0
    assert service_session.execute(select(AiArtifact)).scalars().all() == []


def test_invalid_deepseek_json_is_converted_to_stable_error() -> None:
    async def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            200,
            request=request,
            json={"choices": [{"message": {"content": "不是 JSON"}}]},
        )

    client = HttpDeepSeekClient(
        Settings(deepseek_api_key="test-key"),
        transport=httpx.MockTransport(handler),
    )

    with pytest.raises(ApiError) as captured:
        asyncio.run(client.generate(AiTextGenerationRequest.model_validate(_trainer_request())))

    assert captured.value.code == "deepseek_invalid_output"
