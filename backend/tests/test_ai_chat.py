from __future__ import annotations

import json
from contextlib import contextmanager
from dataclasses import dataclass
from typing import Generator
from uuid import UUID

import httpx
from fastapi.testclient import TestClient

from app.api.ai import (
    get_ai_chat_service,
    get_ai_rate_limiter,
    get_ai_usage_recorder,
)
from app.api.auth import get_current_access_claims
from app.core.config import Settings
from app.core.security import AccessTokenClaims
from app.main import create_app
from app.services.ai_chat import (
    AiChatRequest,
    AiChatResponse,
    AiChatService,
    HttpDeepSeekChatClient,
)


@dataclass
class FakeChatService:
    calls: int = 0

    async def reply(self, user_id: UUID, request: AiChatRequest) -> AiChatResponse:
        del user_id
        self.calls += 1
        return AiChatResponse(
            reply="今天训练的重点是控制节奏，并按计划完成。",
            intent="explain_plan",
            suggested_actions=["view_today_workout"],
            warnings=[],
            provider="test",
            model="test-chat",
        )


@dataclass
class FakeGenerationClient:
    calls: int = 0

    async def reply(self, request: AiChatRequest) -> AiChatResponse:
        del request
        self.calls += 1
        return AiChatResponse(
            reply="按计划完成今天这一项。",
            intent="training_question",
            suggested_actions=[],
            warnings=[],
            provider="test",
            model="test-chat",
        )


class FakeRateLimiter:
    def check(self, _user_id: UUID) -> None:
        return None


class FakeUsageRecorder:
    def record(self, **_metrics) -> None:
        return None


def _claims() -> AccessTokenClaims:
    return AccessTokenClaims(
        user_id=UUID("019f4220-5ce2-7082-b418-5d087d24a4a9"),
        session_id=UUID("019f4220-5ce2-7082-b418-5d087d24a4aa"),
    )


@contextmanager
def _client(service: FakeChatService) -> Generator[TestClient, None, None]:
    app = create_app()
    app.dependency_overrides[get_current_access_claims] = _claims
    app.dependency_overrides[get_ai_chat_service] = lambda: service
    app.dependency_overrides[get_ai_rate_limiter] = lambda: FakeRateLimiter()
    app.dependency_overrides[get_ai_usage_recorder] = lambda: FakeUsageRecorder()
    with TestClient(app) as client:
        yield client
    app.dependency_overrides.clear()


def _request(content: str = "解释一下今天的训练重点") -> dict[str, object]:
    return {
        "contract_version": 1,
        "request_id": "chat-request-1",
        "messages": [{"role": "user", "content": content}],
        "context": {
            "goal": "完成基础训练",
            "sports": ["跑步"],
            "available_minutes": 30,
            "scheduled_minutes": 30,
            "scheduled_period": "晚上",
        },
    }


def test_chat_returns_stateless_response() -> None:
    service = FakeChatService()
    with _client(service) as client:
        response = client.post("/v1/ai/chat", json=_request())

    assert response.status_code == 200
    assert response.json()["intent"] == "explain_plan"
    assert response.json()["suggested_actions"] == ["view_today_workout"]
    assert service.calls == 1


def test_chat_rejects_health_content_before_service_call() -> None:
    service = FakeChatService()
    with _client(service) as client:
        response = client.post(
            "/v1/ai/chat",
            json=_request("结合我的 HRV、睡眠和疼痛安排训练"),
        )

    assert response.status_code == 422
    assert response.json()["code"] == "ai_chat_health_data_not_allowed"
    assert service.calls == 0


def test_chat_requires_login() -> None:
    response = TestClient(create_app()).post("/v1/ai/chat", json=_request())

    assert response.status_code == 401
    assert response.json()["code"] == "access_token_required"


def test_chat_service_reuses_response_for_same_request_id() -> None:
    generation_client = FakeGenerationClient()
    service = AiChatService(generation_client)
    request = AiChatRequest.model_validate(_request())
    user_id = UUID("019f4220-5ce2-7082-b418-5d087d24a4a9")

    import asyncio

    first = asyncio.run(service.reply(user_id, request))
    second = asyncio.run(service.reply(user_id, request))

    assert first == second
    assert generation_client.calls == 1


def test_deepseek_chat_compacts_history_and_records_cache_tokens() -> None:
    captured: dict[str, object] = {}

    def handler(request: httpx.Request) -> httpx.Response:
        captured.update(json.loads(request.content))
        return httpx.Response(
            200,
            json={
                "choices": [
                    {
                        "message": {
                            "content": json.dumps(
                                {
                                    "reply": "按计划完成今天这一项。",
                                    "intent": "training_question",
                                    "suggested_actions": [],
                                    "warnings": [],
                                },
                                ensure_ascii=False,
                            ),
                        },
                    },
                ],
                "usage": {
                    "prompt_tokens": 280,
                    "completion_tokens": 36,
                    "prompt_cache_hit_tokens": 200,
                    "prompt_cache_miss_tokens": 80,
                },
            },
        )

    request = AiChatRequest.model_validate(
        {
            **_request(),
            "messages": [
                {
                    "role": "user",
                    "content": f"第{index}轮-" + ("训练" * 145),
                }
                for index in range(1, 9)
            ],
        },
    )
    client = HttpDeepSeekChatClient(
        Settings(deepseek_api_key="test-key"),
        transport=httpx.MockTransport(handler),
    )

    import asyncio

    response = asyncio.run(client.reply(request))
    body_messages = captured["messages"]
    assert isinstance(body_messages, list)
    user_payload = json.loads(body_messages[1]["content"])

    assert captured["max_tokens"] == 420
    assert len(user_payload["messages"]) == 4
    assert user_payload["messages"][-1]["content"].startswith("第8轮")
    assert response.input_tokens == 280
    assert response.prompt_cache_hit_tokens == 200
    assert response.prompt_cache_miss_tokens == 80
