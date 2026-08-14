from __future__ import annotations

import asyncio
import hashlib
import json
import re
import time
from datetime import timedelta
from typing import Any, Literal, Protocol
from uuid import UUID

import httpx
from pydantic import (
    BaseModel,
    ConfigDict,
    Field,
    ValidationError,
    field_validator,
    model_validator,
)
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import Settings
from app.core.errors import ApiError
from app.core.security import utc_now
from app.models.ai import AiArtifact, AiGenerationJob
from app.services.ai_response_cache import (
    AiResponseCache,
    build_ai_response_cache_key,
    cache_user_domain,
)
from app.services.ai_usage import AiUsageRecorder
from app.services.prompt_budget import PROFILE_PROMPT_POLICY

ProfileFieldCode = Literal[
    "goal",
    "primary_sport",
    "experience_level",
    "weekly_training_days",
    "available_minutes",
    "equipment_access",
]
FollowUpCode = Literal[
    "ask_goal",
    "ask_primary_sport",
    "ask_experience",
    "ask_frequency",
    "ask_duration",
    "ask_equipment",
]
PROFILE_PROPOSAL_PROMPT_CONTRACT = "profile-proposal-v1"
PROFILE_PROPOSAL_ARTIFACT_TYPE = "profile_proposal_v1"
_SENSITIVE_PATTERN = re.compile(
    r"(疼|痛|伤|膝|腰|肩|康复|慢病|心率|hrv|睡眠|"
    r"体重|身高|体脂|公斤|kg|手机号|电话|邮箱|@|"
    r"1[3-9]\d{9}|\d{1,3}\s*岁)",
    re.IGNORECASE,
)
_REQUEST_ID_PATTERN = re.compile(r"^[A-Za-z0-9._-]{1,64}$")


class ProfileKnownFields(BaseModel):
    """客户端本地抽取出的非敏感、枚举化训练偏好。"""

    model_config = ConfigDict(extra="forbid")

    goal: Literal[
        "general_fitness",
        "strength",
        "fat_loss",
        "endurance",
        "race_preparation",
    ] | None = None
    primary_sport: Literal[
        "general_fitness",
        "strength",
        "running",
        "hyrox",
    ] | None = None
    experience_level: Literal["beginner", "intermediate", "advanced"] | None = None
    weekly_training_days: int | None = Field(default=None, ge=1, le=7)
    available_minutes: int | None = Field(default=None, ge=15, le=180)
    equipment_access: list[
        Literal[
            "bodyweight",
            "dumbbell",
            "barbell",
            "gym",
            "treadmill",
            "outdoor",
        ]
    ] | None = Field(default=None, min_length=1, max_length=6)


class ProfileProposalRequest(BaseModel):
    """只允许脱敏后的歧义短片段进入云端。"""

    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    contract_version: Literal[1]
    request_id: str = Field(min_length=1, max_length=64)
    known_fields: ProfileKnownFields
    unresolved_field_codes: list[ProfileFieldCode] = Field(max_length=6)
    ambiguity_fragments: list[str] = Field(max_length=5)

    @field_validator("request_id")
    @classmethod
    def validate_request_id(cls, value: str) -> str:
        if not _REQUEST_ID_PATTERN.fullmatch(value):
            raise ValueError("请求标识格式无效")
        return value

    @field_validator("unresolved_field_codes")
    @classmethod
    def unique_unresolved_fields(
        cls,
        value: list[ProfileFieldCode],
    ) -> list[ProfileFieldCode]:
        return list(dict.fromkeys(value))

    @field_validator("ambiguity_fragments")
    @classmethod
    def validate_sanitized_fragments(cls, value: list[str]) -> list[str]:
        cleaned: list[str] = []
        for fragment in value:
            normalized = fragment.strip()
            if not normalized:
                continue
            if len(normalized) > 240:
                raise ValueError("单个歧义片段不得超过 240 个字符")
            if _SENSITIVE_PATTERN.search(normalized):
                raise ValueError("歧义片段仍包含本地敏感信息")
            cleaned.append(normalized)
        if sum(len(item) for item in cleaned) > 600:
            raise ValueError("歧义片段合计不得超过 600 个字符")
        return cleaned


class ProposedProfileField(BaseModel):
    model_config = ConfigDict(extra="forbid")

    field_code: ProfileFieldCode
    value: str | int | list[str]
    confidence: float = Field(ge=0, le=1)

    @model_validator(mode="after")
    def validate_field_value(self) -> "ProposedProfileField":
        allowed_text: dict[str, set[str]] = {
            "goal": {
                "general_fitness",
                "strength",
                "fat_loss",
                "endurance",
                "race_preparation",
            },
            "primary_sport": {
                "general_fitness",
                "strength",
                "running",
                "hyrox",
            },
            "experience_level": {"beginner", "intermediate", "advanced"},
        }
        if self.field_code in allowed_text:
            if not isinstance(self.value, str) or self.value not in allowed_text[
                self.field_code
            ]:
                raise ValueError("画像字段值不在允许枚举中")
        elif self.field_code == "weekly_training_days":
            if (
                not isinstance(self.value, int)
                or isinstance(self.value, bool)
                or not 1 <= self.value <= 7
            ):
                raise ValueError("每周训练天数无效")
        elif self.field_code == "available_minutes":
            if (
                not isinstance(self.value, int)
                or isinstance(self.value, bool)
                or not 15 <= self.value <= 180
            ):
                raise ValueError("单次训练时长无效")
        else:
            allowed_equipment = {
                "bodyweight",
                "dumbbell",
                "barbell",
                "gym",
                "treadmill",
                "outdoor",
            }
            if (
                not isinstance(self.value, list)
                or not self.value
                or len(self.value) > 6
                or any(item not in allowed_equipment for item in self.value)
            ):
                raise ValueError("器械字段无效")
        return self


class ProfileProposalModelResult(BaseModel):
    """模型输出；服务层会继续裁剪追问并回填生成元数据。"""

    model_config = ConfigDict(extra="forbid")

    proposed_fields: list[ProposedProfileField] = Field(max_length=6)
    missing_field_codes: list[ProfileFieldCode] = Field(max_length=6)
    follow_up_codes: list[FollowUpCode] = Field(max_length=8)
    provider: str = "deepseek"
    model: str = ""
    input_tokens: int | None = Field(default=None, exclude=True)
    output_tokens: int | None = Field(default=None, exclude=True)
    prompt_cache_hit_tokens: int | None = Field(default=None, exclude=True)
    prompt_cache_miss_tokens: int | None = Field(default=None, exclude=True)

    @field_validator(
        "missing_field_codes",
        "follow_up_codes",
    )
    @classmethod
    def unique_codes(cls, value: list[str]) -> list[str]:
        return list(dict.fromkeys(value))


class ProfileProposalClient(Protocol):
    async def generate(
        self,
        request: ProfileProposalRequest,
    ) -> ProfileProposalModelResult:
        """对已脱敏的歧义短片段提出结构化画像字段。"""


class HttpDeepSeekProfileProposalClient:
    """只发送白名单字段和脱敏短片段的 DeepSeek 适配器。"""

    def __init__(
        self,
        settings: Settings,
        transport: httpx.AsyncBaseTransport | None = None,
    ) -> None:
        self._settings = settings
        self._transport = transport

    async def generate(
        self,
        request: ProfileProposalRequest,
    ) -> ProfileProposalModelResult:
        api_key = self._settings.deepseek_api_key
        if api_key is None or not api_key.get_secret_value().strip():
            raise ApiError(503, "deepseek_not_configured", "AI 服务尚未配置")

        system_prompt = (
            "你是 TrainMate 画像提议器。输入已在设备上脱敏。"
            "只能为 unresolved_field_codes 中的字段提出允许枚举值，"
            "不得推断年龄、性别、身体指标、健康、伤病或联系方式。"
            "不修改用户档案，只返回 JSON：proposed_fields、"
            "missing_field_codes、follow_up_codes。追问只能返回代码。"
        )
        user_prompt = json.dumps(
            {
                "known_fields": request.known_fields.model_dump(
                    mode="json",
                    exclude_none=True,
                ),
                "unresolved_field_codes": request.unresolved_field_codes,
                "ambiguity_fragments": request.ambiguity_fragments,
            },
            ensure_ascii=False,
            separators=(",", ":"),
        )
        PROFILE_PROMPT_POLICY.validate_required_parts(system_prompt, user_prompt)
        payload = {
            "model": self._settings.deepseek_model,
            "messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt},
            ],
            "temperature": 0,
            "max_tokens": PROFILE_PROMPT_POLICY.max_output_tokens,
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
                "画像提议超时，已退回本地表单。",
            ) from error
        except httpx.RequestError as error:
            raise ApiError(
                502,
                "deepseek_connection_failed",
                "画像提议暂时不可用，已退回本地表单。",
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
            return ProfileProposalModelResult.model_validate(parsed)
        except (KeyError, TypeError, ValueError) as error:
            raise ApiError(
                502,
                "profile_proposal_invalid",
                "画像提议格式无效，已退回本地表单。",
            ) from error


class ProfileProposalService:
    """生成待确认画像提议；原始片段不持久化。"""

    def __init__(
        self,
        *,
        session: Session,
        settings: Settings,
        client: ProfileProposalClient,
        response_cache: AiResponseCache | None = None,
    ) -> None:
        self._session = session
        self._settings = settings
        self._client = client
        self._response_cache = response_cache

    async def propose(
        self,
        user_id: UUID,
        request: ProfileProposalRequest,
    ) -> tuple[AiArtifact, bool]:
        started_at = time.perf_counter()
        if not self._settings.profile_proposal_enabled:
            raise ApiError(
                503,
                "profile_proposal_unavailable",
                "画像提议暂时关闭，请使用本地表单建档。",
            )
        digest = _request_digest(request, self._settings.deepseek_model)
        cached = self._find_cached(user_id, digest)
        if cached is not None:
            self._record_usage(
                provider=cached.provider,
                model=cached.model,
                input_tokens=0,
                output_tokens=0,
                prompt_cache_hit_tokens=0,
                prompt_cache_miss_tokens=0,
                latency_ms=_elapsed_ms(started_at),
                result_code="cached",
                request_id=request.request_id,
            )
            self._session.refresh(cached)
            return cached, True

        mode = "cloud_adaptation"
        app_cache_hit = False
        if not request.ambiguity_fragments:
            result = _local_fallback(request)
            mode = "local_safe_fallback"
        else:
            try:
                if self._response_cache is None:
                    result = await self._client.generate(request)
                else:
                    cache_key = build_ai_response_cache_key(
                        capability="profile_proposal",
                        model=self._settings.deepseek_model,
                        prompt_contract_version=PROFILE_PROPOSAL_PROMPT_CONTRACT,
                        skill_hash="none",
                        knowledge_version="none",
                        context_digest=digest,
                        user_domain_hash=cache_user_domain(user_id),
                    )

                    async def generate_for_cache() -> dict[str, object]:
                        generated = await self._client.generate(request)
                        return _result_to_cache(generated)

                    cached_result, app_cache_hit = (
                        await self._response_cache.get_or_compute(
                            key=cache_key,
                            ttl_seconds=10 * 60,
                            producer=generate_for_cache,
                        )
                    )
                    result = _result_from_cache(
                        cached_result,
                        cache_hit=app_cache_hit,
                    )
            except (ApiError, ValidationError):
                app_cache_hit = False
                result = _local_fallback(request)
                mode = "local_safe_fallback"
        artifact = self._persist(
            user_id=user_id,
            digest=digest,
            request=request,
            result=result,
            generation_mode=mode,
        )
        self._record_usage(
            provider=result.provider,
            model=result.model or self._settings.deepseek_model,
            input_tokens=result.input_tokens,
            output_tokens=result.output_tokens,
            prompt_cache_hit_tokens=result.prompt_cache_hit_tokens,
            prompt_cache_miss_tokens=result.prompt_cache_miss_tokens,
            latency_ms=_elapsed_ms(started_at),
            result_code="cached" if app_cache_hit else mode,
            request_id=request.request_id,
        )
        self._session.refresh(artifact)
        return artifact, app_cache_hit

    def _find_cached(self, user_id: UUID, digest: str) -> AiArtifact | None:
        cutoff = utc_now() - timedelta(minutes=10)
        statement = (
            select(AiArtifact)
            .where(
                AiArtifact.user_id == user_id,
                AiArtifact.artifact_type == PROFILE_PROPOSAL_ARTIFACT_TYPE,
                AiArtifact.context_digest == digest,
                AiArtifact.generated_at >= cutoff,
            )
            .order_by(AiArtifact.generated_at.desc())
            .limit(1)
        )
        return self._session.execute(statement).scalar_one_or_none()

    def _persist(
        self,
        *,
        user_id: UUID,
        digest: str,
        request: ProfileProposalRequest,
        result: ProfileProposalModelResult,
        generation_mode: str,
    ) -> AiArtifact:
        provider = result.provider
        model = result.model or (
            "deterministic-profile-form-v1"
            if generation_mode == "local_safe_fallback"
            else self._settings.deepseek_model
        )
        job = AiGenerationJob(
            user_id=user_id,
            capability="trainer",
            artifact_type=PROFILE_PROPOSAL_ARTIFACT_TYPE,
            provider=provider,
            model=model,
            context_digest=digest,
            state="completed",
            completed_at=utc_now(),
        )
        self._session.add(job)
        self._session.flush()
        proposed = [
            field.model_dump(mode="json")
            for field in result.proposed_fields
            if field.field_code in request.unresolved_field_codes
        ]
        artifact = AiArtifact(
            job_id=job.id,
            user_id=user_id,
            capability="trainer",
            artifact_type=PROFILE_PROPOSAL_ARTIFACT_TYPE,
            schema_version=1,
            decision_status="pending",
            context_digest=digest,
            payload={
                "proposal_status": "pending",
                "proposed_fields": proposed,
                "missing_field_codes": result.missing_field_codes,
                "follow_up_codes": result.follow_up_codes[:5],
                "generation_meta": {
                    "prompt_contract_version": PROFILE_PROPOSAL_PROMPT_CONTRACT,
                    "knowledge_snapshot_version": None,
                    "generation_mode": generation_mode,
                    "app_cache_hit": False,
                    "input_tokens": result.input_tokens or 0,
                    "output_tokens": result.output_tokens or 0,
                    "prompt_cache_hit_tokens": (
                        result.prompt_cache_hit_tokens or 0
                    ),
                    "prompt_cache_miss_tokens": (
                        result.prompt_cache_miss_tokens or 0
                    ),
                },
            },
            warnings=[],
            provider=provider,
            model=model,
        )
        self._session.add(artifact)
        self._session.commit()
        self._session.refresh(artifact)
        return artifact

    def _record_usage(self, **metrics: Any) -> None:
        AiUsageRecorder(self._session).record(
            capability="profile_proposal",
            prompt_contract_version=PROFILE_PROPOSAL_PROMPT_CONTRACT,
            **metrics,
        )


def _local_fallback(
    request: ProfileProposalRequest,
) -> ProfileProposalModelResult:
    follow_up_by_field: dict[str, FollowUpCode] = {
        "goal": "ask_goal",
        "primary_sport": "ask_primary_sport",
        "experience_level": "ask_experience",
        "weekly_training_days": "ask_frequency",
        "available_minutes": "ask_duration",
        "equipment_access": "ask_equipment",
    }
    return ProfileProposalModelResult(
        proposed_fields=[],
        missing_field_codes=request.unresolved_field_codes,
        follow_up_codes=[
            follow_up_by_field[field]
            for field in request.unresolved_field_codes[:5]
        ],
        provider="local",
        model="deterministic-profile-form-v1",
        input_tokens=0,
        output_tokens=0,
        prompt_cache_hit_tokens=0,
        prompt_cache_miss_tokens=0,
    )


def _request_digest(request: ProfileProposalRequest, model: str) -> str:
    canonical = json.dumps(
        {
            "capability": "profile_proposal",
            "model": model,
            "prompt_contract_version": PROFILE_PROPOSAL_PROMPT_CONTRACT,
            "known_fields": request.known_fields.model_dump(
                mode="json",
                exclude_none=True,
            ),
            "unresolved_field_codes": request.unresolved_field_codes,
            "ambiguity_fragments": request.ambiguity_fragments,
        },
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    )
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def _result_to_cache(result: ProfileProposalModelResult) -> dict[str, object]:
    return {
        "proposed_fields": [
            item.model_dump(mode="json") for item in result.proposed_fields
        ],
        "missing_field_codes": result.missing_field_codes,
        "follow_up_codes": result.follow_up_codes,
        "provider": result.provider,
        "model": result.model,
        "input_tokens": result.input_tokens,
        "output_tokens": result.output_tokens,
        "prompt_cache_hit_tokens": result.prompt_cache_hit_tokens,
        "prompt_cache_miss_tokens": result.prompt_cache_miss_tokens,
    }


def _result_from_cache(
    payload: dict[str, object],
    *,
    cache_hit: bool,
) -> ProfileProposalModelResult:
    result = ProfileProposalModelResult.model_validate(payload)
    if not cache_hit:
        return result
    return result.model_copy(
        update={
            "input_tokens": 0,
            "output_tokens": 0,
            "prompt_cache_hit_tokens": 0,
            "prompt_cache_miss_tokens": 0,
        },
    )


def _optional_int(value: object) -> int | None:
    if isinstance(value, bool):
        return None
    return int(value) if isinstance(value, int | float) else None


def _elapsed_ms(started_at: float) -> int:
    return max(0, round((time.perf_counter() - started_at) * 1000))
