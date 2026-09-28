from __future__ import annotations

import asyncio
import hashlib
import json
import time
from dataclasses import dataclass
from typing import Literal, Protocol
from uuid import UUID

import httpx
from pydantic import BaseModel, ConfigDict, Field, ValidationError, field_validator

from app.core.config import Settings
from app.core.errors import ApiError
from app.services.ai_response_cache import (
    AiResponseCache,
    build_ai_idempotency_key,
    build_ai_response_cache_key,
    cache_user_domain,
)
from app.services.prompt_budget import CHAT_PROMPT_POLICY

AiChatRequestIntent = Literal[
    "explain_today_training",
    "explain_plan_structure",
    "explain_training_focus",
]
AiChatSportCode = Literal[
    "marathon",
    "trail_running",
    "strength",
    "hyrox",
    "general_fitness",
]
AiChatScheduledPeriod = Literal["morning", "midday", "evening", "late_night"]
AiChatIntent = Literal[
    "training_question",
    "explain_plan",
    "open_plan_generator",
]
AiChatAction = Literal[
    "view_today_workout",
    "view_active_plan",
    "open_plan_generator",
]
AI_CHAT_PROMPT_CONTRACT = "ai-chat-v3-structured"


class AiChatContext(BaseModel):
    """只允许固定代码和数值进入云端的训练上下文。"""

    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    sport_codes: list[AiChatSportCode] = Field(default_factory=list, max_length=4)
    available_minutes: int = Field(default=30, ge=0, le=360)
    scheduled_minutes: int | None = Field(default=None, ge=0, le=360)
    scheduled_period: AiChatScheduledPeriod | None = None

    @field_validator("sport_codes")
    @classmethod
    def deduplicate_sport_codes(
        cls,
        values: list[AiChatSportCode],
    ) -> list[AiChatSportCode]:
        return list(dict.fromkeys(values))[:4]


class AiChatRequest(BaseModel):
    """结构化聊天请求；协议中不存在可承载健康正文的字段。"""

    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    contract_version: Literal[2]
    request_id: str = Field(min_length=8, max_length=80)
    intent: AiChatRequestIntent
    context: AiChatContext


class AiChatResponse(BaseModel):
    """Flutter 可直接渲染的聊天回复。"""

    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    reply: str = Field(min_length=1, max_length=1200)
    intent: AiChatIntent = "training_question"
    suggested_actions: list[AiChatAction] = Field(default_factory=list, max_length=3)
    warnings: list[str] = Field(default_factory=list, max_length=4)
    provider: str = Field(min_length=1, max_length=32)
    model: str = Field(min_length=1, max_length=80)
    input_tokens: int | None = Field(default=None, exclude=True)
    output_tokens: int | None = Field(default=None, exclude=True)
    prompt_cache_hit_tokens: int | None = Field(default=None, exclude=True)
    prompt_cache_miss_tokens: int | None = Field(default=None, exclude=True)
    app_cache_hit: bool = Field(default=False, exclude=True)

    @field_validator("warnings")
    @classmethod
    def normalize_warnings(cls, values: list[str]) -> list[str]:
        return [value.strip()[:160] for value in values if value.strip()][:4]


class ChatGenerationClient(Protocol):
    async def reply(self, request: AiChatRequest) -> AiChatResponse:
        """生成一条经过结构校验的教练回复。"""


class HttpDeepSeekChatClient:
    """DeepSeek 无状态聊天适配器，不记录提示词或回复。"""

    def __init__(
        self,
        settings: Settings,
        transport: httpx.AsyncBaseTransport | None = None,
    ) -> None:
        self._settings = settings
        self._transport = transport

    async def reply(self, request: AiChatRequest) -> AiChatResponse:
        api_key = self._settings.deepseek_api_key
        if api_key is None or not api_key.get_secret_value().strip():
            raise ApiError(503, "deepseek_not_configured", "AI 服务尚未配置")

        system_prompt = (
            "你是 TrainMate 训练教练。使用简洁、具体、描述性的中文，"
            "一次只讲一个重点，不使用羞耻、恐惧或空泛夸奖。"
            "不得给出医疗判断、热量目标、体重目标或体脂目标。"
            "不得声称已经修改训练计划；需要改计划时只建议打开计划生成器。"
            "只返回 JSON：reply、intent、suggested_actions、warnings。"
        )
        user_prompt = json.dumps(
            {
                "intent": request.intent,
                "context": request.context.model_dump(
                    mode="json",
                    exclude_none=True,
                ),
            },
            ensure_ascii=False,
            separators=(",", ":"),
        )
        CHAT_PROMPT_POLICY.validate_required_parts(system_prompt, user_prompt)
        payload = {
            "model": self._settings.deepseek_model,
            "messages": [
                {
                    "role": "system",
                    "content": system_prompt,
                },
                {
                    "role": "user",
                    "content": user_prompt,
                },
            ],
            "temperature": 0,
            "max_tokens": CHAT_PROMPT_POLICY.max_output_tokens,
            "response_format": {"type": "json_object"},
        }
        endpoint = f"{self._settings.deepseek_base_url.rstrip('/')}/chat/completions"
        headers = {
            "Authorization": f"Bearer {api_key.get_secret_value()}",
            "Content-Type": "application/json",
        }
        try:
            async with asyncio.timeout(self._settings.ai_generation_timeout_seconds):
                async with httpx.AsyncClient(
                    timeout=httpx.Timeout(
                        self._settings.ai_generation_timeout_seconds,
                    ),
                    transport=self._transport,
                ) as client:
                    response = await client.post(
                        endpoint,
                        headers=headers,
                        json=payload,
                    )
        except (TimeoutError, httpx.TimeoutException) as error:
            raise ApiError(
                504,
                "deepseek_timeout",
                "AI 回复超时，请稍后重试",
            ) from error
        except httpx.RequestError as error:
            raise ApiError(
                502,
                "deepseek_connection_failed",
                "AI 服务暂时无法连接，请稍后重试",
            ) from error

        if response.status_code == 429:
            raise ApiError(429, "deepseek_rate_limited", "AI 服务繁忙，请稍后重试")
        if response.status_code >= 400:
            raise ApiError(502, "deepseek_upstream_failed", "AI 服务返回异常")

        try:
            body = response.json()
            content = body["choices"][0]["message"]["content"]
            if not isinstance(content, str):
                raise TypeError
            parsed = json.loads(content)
            parsed["provider"] = "deepseek"
            parsed["model"] = self._settings.deepseek_model
            usage = body.get("usage", {})
            if isinstance(usage, dict):
                parsed["input_tokens"] = _optional_int(
                    usage.get("prompt_tokens"),
                )
                parsed["output_tokens"] = _optional_int(
                    usage.get("completion_tokens"),
                )
                parsed["prompt_cache_hit_tokens"] = _optional_int(
                    usage.get("prompt_cache_hit_tokens"),
                )
                parsed["prompt_cache_miss_tokens"] = _optional_int(
                    usage.get("prompt_cache_miss_tokens"),
                )
            return AiChatResponse.model_validate(parsed)
        except (KeyError, IndexError, TypeError, ValueError, ValidationError) as error:
            raise ApiError(
                502,
                "deepseek_invalid_output",
                "AI 返回了无法使用的训练回复，请重试。",
            ) from error


@dataclass(frozen=True)
class _CachedReply:
    expires_at: float
    request_digest: str
    response: AiChatResponse


class AiChatService:
    """执行隐私复核和短时幂等缓存，不持久化聊天内容。"""

    def __init__(
        self,
        client: ChatGenerationClient,
        *,
        cache_ttl_seconds: int = 300,
        response_cache: AiResponseCache | None = None,
        model: str = "deepseek-v4-flash",
    ) -> None:
        self._client = client
        self._cache_ttl_seconds = cache_ttl_seconds
        self._response_cache = response_cache
        self._model = model
        self._cache: dict[tuple[UUID, str], _CachedReply] = {}
        self._inflight: dict[
            tuple[UUID, str],
            tuple[str, asyncio.Task[AiChatResponse]],
        ] = {}
        self._lock = asyncio.Lock()

    async def reply(self, user_id: UUID, request: AiChatRequest) -> AiChatResponse:
        request_digest = _request_digest(request)
        if self._response_cache is not None:
            binding = await self._response_cache.bind_request_digest(
                key=build_ai_idempotency_key(
                    user_id=user_id,
                    request_id=request.request_id,
                ),
                request_digest=request_digest,
                ttl_seconds=self._cache_ttl_seconds,
            )
            if binding == "conflict":
                raise _idempotency_conflict()
            if binding == "unavailable":
                return await self._reply_with_local_cache(
                    user_id,
                    request,
                    request_digest,
                )
            cache_key = build_ai_response_cache_key(
                capability="chat",
                model=self._model,
                prompt_contract_version=AI_CHAT_PROMPT_CONTRACT,
                skill_hash="none",
                knowledge_version="none",
                context_digest=request_digest,
                user_domain_hash=cache_user_domain(user_id),
            )

            async def generate_for_cache() -> dict[str, object]:
                response = await self._client.reply(request)
                return _response_to_cache(response)

            cached, cache_hit = await self._response_cache.get_or_compute(
                key=cache_key,
                ttl_seconds=self._cache_ttl_seconds,
                producer=generate_for_cache,
            )
            return _response_from_cache(cached, cache_hit=cache_hit)

        return await self._reply_with_local_cache(
            user_id,
            request,
            request_digest,
        )

    async def _reply_with_local_cache(
        self,
        user_id: UUID,
        request: AiChatRequest,
        request_digest: str,
    ) -> AiChatResponse:
        """Redis 不可用时复用进程内短期结果，并保留冲突检测。"""
        key = (user_id, request.request_id)
        now = time.monotonic()
        async with self._lock:
            self._cache = {
                cache_key: item
                for cache_key, item in self._cache.items()
                if item.expires_at > now
            }
            cached = self._cache.get(key)
            if cached is not None:
                if cached.request_digest != request_digest:
                    raise _idempotency_conflict()
                return cached.response
            inflight = self._inflight.get(key)
            if inflight is not None:
                bound_digest, task = inflight
                if bound_digest != request_digest:
                    raise _idempotency_conflict()
            else:
                task = asyncio.create_task(self._client.reply(request))
                self._inflight[key] = (request_digest, task)

        try:
            response = await task
        finally:
            if task.done():
                async with self._lock:
                    current = self._inflight.get(key)
                    if current is not None and current[1] is task:
                        self._inflight.pop(key, None)
        async with self._lock:
            self._cache[key] = _CachedReply(
                expires_at=time.monotonic() + self._cache_ttl_seconds,
                request_digest=request_digest,
                response=response,
            )
        return response


def _response_to_cache(response: AiChatResponse) -> dict[str, object]:
    return {
        "reply": response.reply,
        "intent": response.intent,
        "suggested_actions": response.suggested_actions,
        "warnings": response.warnings,
        "provider": response.provider,
        "model": response.model,
        "input_tokens": response.input_tokens,
        "output_tokens": response.output_tokens,
        "prompt_cache_hit_tokens": response.prompt_cache_hit_tokens,
        "prompt_cache_miss_tokens": response.prompt_cache_miss_tokens,
    }


def _response_from_cache(
    payload: dict[str, object],
    *,
    cache_hit: bool,
) -> AiChatResponse:
    response = AiChatResponse.model_validate(payload)
    if not cache_hit:
        return response
    return response.model_copy(
        update={
            "input_tokens": 0,
            "output_tokens": 0,
            "prompt_cache_hit_tokens": 0,
            "prompt_cache_miss_tokens": 0,
            "app_cache_hit": True,
        },
    )


def _request_digest(request: AiChatRequest) -> str:
    material = request.model_dump(mode="json", exclude={"request_id"})
    encoded = json.dumps(
        material,
        ensure_ascii=True,
        sort_keys=True,
        separators=(",", ":"),
    )
    return hashlib.sha256(encoded.encode("utf-8")).hexdigest()


def _idempotency_conflict() -> ApiError:
    return ApiError(
        409,
        "ai_chat_idempotency_conflict",
        "同一请求标识不能用于不同的训练问题，请重新发送。",
    )


def _optional_int(value: object) -> int | None:
    return value if isinstance(value, int) else None
