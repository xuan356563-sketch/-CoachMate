from __future__ import annotations

import asyncio
import json
from contextlib import contextmanager
from dataclasses import dataclass
from typing import Any, Generator
from uuid import UUID

import httpx
import pytest
from fastapi.testclient import TestClient

from app.api.ai import (
    get_ai_chat_service,
    get_ai_rate_limiter,
    get_ai_usage_recorder,
)
from app.api.auth import get_current_access_claims
from app.core.config import Settings
from app.core.errors import ApiError
from app.core.security import AccessTokenClaims
from app.main import create_app
from app.services.ai_chat import (
    AiChatRequest,
    AiChatResponse,
    AiChatService,
    HttpDeepSeekChatClient,
)
from app.services.ai_response_cache import AiResponseCache


@dataclass
class FakeChatService:
    calls: int = 0

    async def reply(self, user_id: UUID, request: AiChatRequest) -> AiChatResponse:
        del user_id, request
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


class InMemoryAsyncRedis:
    def __init__(self) -> None:
        self.values: dict[str, str] = {}

    async def get(self, name: str) -> str | None:
        return self.values.get(name)

    async def set(
        self,
        name: str,
        value: str,
        *,
        ex: int | None = None,
        nx: bool = False,
    ) -> bool:
        del ex
        if nx and name in self.values:
            return False
        self.values[name] = value
        return True

    async def eval(
        self,
        script: str,
        numkeys: int,
        *keys_and_args: str,
    ) -> int:
        del script, numkeys
        key, owner = keys_and_args
        if self.values.get(key) != owner:
            return 0
        del self.values[key]
        return 1


class FailingAsyncRedis(InMemoryAsyncRedis):
    async def get(self, name: str) -> str | None:
        del name
        raise OSError("测试 Redis 不可用")

    async def set(
        self,
        name: str,
        value: str,
        *,
        ex: int | None = None,
        nx: bool = False,
    ) -> bool:
        del name, value, ex, nx
        raise OSError("测试 Redis 不可用")


class FakeRateLimiter:
    def check(self, _user_id: UUID) -> None:
        return None


class FakeUsageRecorder:
    def record(self, **_metrics: Any) -> None:
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


def _request(
    *,
    request_id: str = "chat-request-1",
    intent: str = "explain_today_training",
) -> dict[str, object]:
    return {
        "contract_version": 2,
        "request_id": request_id,
        "intent": intent,
        "context": {
            "sport_codes": ["marathon", "strength"],
            "available_minutes": 30,
            "scheduled_minutes": 30,
            "scheduled_period": "evening",
        },
    }


def _legacy_request(content: str) -> dict[str, object]:
    return {
        "contract_version": 1,
        "request_id": "chat-request-1",
        "messages": [{"role": "user", "content": content}],
        "context": {
            "goal": "完成基础训练",
            "sports": ["跑步"],
            "available_minutes": 30,
        },
    }


def test_v1_chat_contract_is_retired_without_service_call() -> None:
    service = FakeChatService()
    with _client(service) as client:
        response = client.post(
            "/v1/ai/chat",
            json=_legacy_request("膝盖不舒服，解释今天训练重点"),
        )

    assert response.status_code == 410
    assert response.json()["code"] == "ai_chat_contract_retired"
    assert service.calls == 0


def test_structured_chat_returns_stateless_response() -> None:
    service = FakeChatService()
    with _client(service) as client:
        response = client.post("/v2/ai/chat", json=_request())

    assert response.status_code == 200
    assert response.json()["intent"] == "explain_plan"
    assert response.json()["suggested_actions"] == ["view_today_workout"]
    assert service.calls == 1


@pytest.mark.parametrize("content", ["膝盖不舒服", "胸闷眩晕", "血糖偏高"])
def test_structured_chat_rejects_any_free_text_field(content: str) -> None:
    service = FakeChatService()
    request = _request()
    request["messages"] = [{"role": "user", "content": content}]
    with _client(service) as client:
        response = client.post("/v2/ai/chat", json=request)

    assert response.status_code == 422
    assert response.json()["code"] == "ai_chat_request_invalid"
    assert service.calls == 0


def test_structured_chat_rejects_unknown_sport_and_period() -> None:
    service = FakeChatService()
    request = _request()
    context = request["context"]
    assert isinstance(context, dict)
    context["sport_codes"] = ["rehab", "fat_loss"]
    context["scheduled_period"] = "晚间"
    with _client(service) as client:
        response = client.post("/v2/ai/chat", json=request)

    assert response.status_code == 422
    assert service.calls == 0


def test_structured_chat_requires_login() -> None:
    response = TestClient(create_app()).post("/v2/ai/chat", json=_request())

    assert response.status_code == 401
    assert response.json()["code"] == "access_token_required"


def test_chat_service_reuses_response_for_same_request_id_and_payload() -> None:
    generation_client = FakeGenerationClient()
    service = AiChatService(generation_client)
    request = AiChatRequest.model_validate(_request())
    user_id = UUID("019f4220-5ce2-7082-b418-5d087d24a4a9")

    first = asyncio.run(service.reply(user_id, request))
    second = asyncio.run(service.reply(user_id, request))

    assert first == second
    assert generation_client.calls == 1


def test_chat_service_rejects_changed_payload_for_same_request_id() -> None:
    generation_client = FakeGenerationClient()
    service = AiChatService(generation_client)
    user_id = UUID("019f4220-5ce2-7082-b418-5d087d24a4a9")
    first = AiChatRequest.model_validate(_request())
    changed = AiChatRequest.model_validate(
        _request(intent="explain_plan_structure"),
    )

    asyncio.run(service.reply(user_id, first))
    with pytest.raises(ApiError) as captured:
        asyncio.run(service.reply(user_id, changed))

    assert captured.value.status_code == 409
    assert captured.value.code == "ai_chat_idempotency_conflict"
    assert generation_client.calls == 1


def test_chat_service_keeps_same_request_id_independent_between_users() -> None:
    generation_client = FakeGenerationClient()
    service = AiChatService(generation_client)
    first = AiChatRequest.model_validate(_request())
    changed = AiChatRequest.model_validate(
        _request(intent="explain_plan_structure"),
    )

    asyncio.run(
        service.reply(UUID("019f4220-5ce2-7082-b418-5d087d24a4a9"), first),
    )
    asyncio.run(
        service.reply(UUID("019f4220-5ce2-7082-b418-5d087d24a4aa"), changed),
    )

    assert generation_client.calls == 2


def test_redis_binding_rejects_changed_payload_for_same_request_id() -> None:
    generation_client = FakeGenerationClient()
    response_cache = AiResponseCache(redis_client=InMemoryAsyncRedis())
    service = AiChatService(generation_client, response_cache=response_cache)
    user_id = UUID("019f4220-5ce2-7082-b418-5d087d24a4a9")
    first = AiChatRequest.model_validate(_request())
    changed = AiChatRequest.model_validate(
        _request(intent="explain_training_focus"),
    )

    asyncio.run(service.reply(user_id, first))
    with pytest.raises(ApiError) as captured:
        asyncio.run(service.reply(user_id, changed))

    assert captured.value.code == "ai_chat_idempotency_conflict"
    assert generation_client.calls == 1


def test_redis_failure_reuses_local_response_for_same_request() -> None:
    generation_client = FakeGenerationClient()
    response_cache = AiResponseCache(redis_client=FailingAsyncRedis())
    service = AiChatService(generation_client, response_cache=response_cache)
    request = AiChatRequest.model_validate(_request())
    user_id = UUID("019f4220-5ce2-7082-b418-5d087d24a4a9")

    first = asyncio.run(service.reply(user_id, request))
    second = asyncio.run(service.reply(user_id, request))

    assert first == second
    assert generation_client.calls == 1


def test_redis_failure_coalesces_concurrent_same_requests() -> None:
    async def scenario() -> tuple[list[AiChatResponse], int]:
        generation_client = FakeGenerationClient()
        response_cache = AiResponseCache(redis_client=FailingAsyncRedis())
        service = AiChatService(generation_client, response_cache=response_cache)
        request = AiChatRequest.model_validate(_request())
        user_id = UUID("019f4220-5ce2-7082-b418-5d087d24a4a9")
        responses = await asyncio.gather(
            *[service.reply(user_id, request) for _ in range(4)],
        )
        return responses, generation_client.calls

    responses, calls = asyncio.run(scenario())

    assert all(response == responses[0] for response in responses)
    assert calls == 1


def test_deepseek_chat_only_receives_structured_intent_and_codes() -> None:
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
                    "prompt_tokens": 80,
                    "completion_tokens": 36,
                    "prompt_cache_hit_tokens": 20,
                    "prompt_cache_miss_tokens": 60,
                },
            },
        )

    request = AiChatRequest.model_validate(_request())
    client = HttpDeepSeekChatClient(
        Settings(deepseek_api_key="test-key"),
        transport=httpx.MockTransport(handler),
    )

    response = asyncio.run(client.reply(request))
    body_messages = captured["messages"]
    assert isinstance(body_messages, list)
    user_payload = json.loads(body_messages[1]["content"])

    assert captured["max_tokens"] == 420
    assert user_payload == {
        "intent": "explain_today_training",
        "context": {
            "sport_codes": ["marathon", "strength"],
            "available_minutes": 30,
            "scheduled_minutes": 30,
            "scheduled_period": "evening",
        },
    }
    encoded = json.dumps(user_payload, ensure_ascii=False)
    assert "messages" not in encoded
    assert "goal" not in encoded
    assert "膝盖" not in encoded
    assert response.input_tokens == 80
    assert response.prompt_cache_hit_tokens == 20
    assert response.prompt_cache_miss_tokens == 60
