from __future__ import annotations

import asyncio
import hashlib
import json
import time
from datetime import date, timedelta
from typing import Any, Literal, Protocol
from uuid import UUID

import httpx
from pydantic import BaseModel, ConfigDict, Field, ValidationError, field_validator
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
from app.services.prompt_budget import PLAN_REVISION_PROMPT_POLICY
from app.services.training_prescription import ValidatedTrainingPrescription
from app.services.training_prescription_v2 import AdaptationSignals

PLAN_REVISION_PROMPT_CONTRACT = "plan-revision-v1"
PLAN_REVISION_ARTIFACT_TYPE = "plan_revision_v1"

SafetyConstraintCode = Literal[
    "no_increase",
    "avoid_impact",
    "limit_duration",
    "keep_recovery_spacing",
]
RevisionReasonCode = Literal[
    "consecutive_missed",
    "schedule_changed",
    "equipment_changed",
    "remaining_cycle_conflict",
    "local_safe_fallback",
]


class CompletionSummary(BaseModel):
    model_config = ConfigDict(extra="forbid")

    completed_sessions: int = Field(ge=0, le=28)
    missed_sessions: int = Field(ge=0, le=28)


class PlanRevisionRequest(BaseModel):
    """只接收枚举化计划上下文，不接收健康原因或自由文本。"""

    model_config = ConfigDict(extra="forbid")

    contract_version: Literal[1]
    client_context_digest: str = Field(pattern=r"^[0-9a-f]{64}$")
    remaining_dates: list[date] = Field(min_length=2, max_length=28)
    completion_summary: CompletionSummary
    schedule_change_dates: list[date] = Field(default_factory=list, max_length=14)
    available_minutes: int = Field(ge=20, le=180)
    equipment_access: list[
        Literal[
            "bodyweight",
            "dumbbell",
            "barbell",
            "gym",
            "treadmill",
            "outdoor",
            "kettlebell",
            "machines",
            "cardio_machines",
        ]
    ] = Field(min_length=1, max_length=6)
    equipment_changed: bool = False
    safety_constraint_codes: list[SafetyConstraintCode] = Field(
        default_factory=list,
        max_length=4,
    )
    adaptation_signals: AdaptationSignals | None = None
    current_prescription: ValidatedTrainingPrescription
    force: bool = False

    @field_validator(
        "remaining_dates",
        "schedule_change_dates",
        "equipment_access",
        "safety_constraint_codes",
    )
    @classmethod
    def reject_duplicates(cls, values: list[Any]) -> list[Any]:
        if len(values) != len(set(values)):
            raise ValueError("重排上下文包含重复值")
        return values


class PlanRevisionDiff(BaseModel):
    model_config = ConfigDict(extra="forbid")

    session_index: int = Field(ge=0, le=5)
    before_training_type: str = Field(min_length=1, max_length=32)
    after_training_type: str = Field(min_length=1, max_length=32)
    before_duration_minutes: int = Field(ge=20, le=180)
    after_duration_minutes: int = Field(ge=20, le=180)
    reason_code: RevisionReasonCode


class PlanRevisionModelResult(BaseModel):
    model_config = ConfigDict(extra="forbid")

    revised_prescription: ValidatedTrainingPrescription
    differences: list[PlanRevisionDiff] = Field(min_length=1, max_length=6)
    provider: str = Field(default="deepseek", exclude=True)
    model: str = Field(default="", exclude=True)
    input_tokens: int | None = Field(default=None, exclude=True)
    output_tokens: int | None = Field(default=None, exclude=True)
    prompt_cache_hit_tokens: int | None = Field(default=None, exclude=True)
    prompt_cache_miss_tokens: int | None = Field(default=None, exclude=True)


class PlanRevisionClient(Protocol):
    async def generate(self, request: PlanRevisionRequest) -> PlanRevisionModelResult:
        """生成剩余周期的结构化差异。"""


class HttpDeepSeekPlanRevisionClient:
    """使用稳定安全前缀和严格 Schema 生成重排候选。"""

    def __init__(self, settings: Settings) -> None:
        self._settings = settings

    async def generate(self, request: PlanRevisionRequest) -> PlanRevisionModelResult:
        api_key = (
            self._settings.deepseek_api_key.get_secret_value()
            if self._settings.deepseek_api_key is not None
            else ""
        )
        if not api_key:
            raise ApiError(503, "deepseek_not_configured", "AI 服务尚未配置")
        system_prompt = (
            "你是 TrainMate 剩余周期重排器。只返回 JSON。"
            "不得推断或输出疾病、疼痛、伤病原因；安全约束代码必须原样遵守。"
            "不得增加每周课程数；no_increase 时不得增加课程时长或强度。"
            "输出 revised_prescription 和 differences。"
            "differences 每项只含 session_index、before_training_type、"
            "after_training_type、before_duration_minutes、"
            "after_duration_minutes、reason_code。"
        )
        user_prompt = json.dumps(
            request.model_dump(mode="json", exclude={"force"}),
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
        )
        PLAN_REVISION_PROMPT_POLICY.validate_required_parts(
            system_prompt,
            user_prompt,
        )
        endpoint = (
            f"{self._settings.deepseek_base_url.rstrip('/')}/chat/completions"
        )
        try:
            async with asyncio.timeout(
                self._settings.ai_generation_timeout_seconds,
            ):
                async with httpx.AsyncClient(
                    timeout=httpx.Timeout(
                        self._settings.ai_generation_timeout_seconds,
                    ),
                ) as client:
                    response = await client.post(
                        endpoint,
                        headers={
                            "Authorization": f"Bearer {api_key}",
                            "Content-Type": "application/json",
                        },
                        json={
                            "model": self._settings.deepseek_model,
                            "temperature": 0,
                            "max_tokens": (
                                PLAN_REVISION_PROMPT_POLICY.max_output_tokens
                            ),
                            "response_format": {"type": "json_object"},
                            "messages": [
                                {"role": "system", "content": system_prompt},
                                {"role": "user", "content": user_prompt},
                            ],
                        },
                    )
        except TimeoutError as error:
            raise ApiError(
                504,
                "plan_revision_timeout",
                "计划重排超时，已保留当前计划。",
            ) from error
        except httpx.RequestError as error:
            raise ApiError(
                502,
                "plan_revision_connection_failed",
                "计划重排暂时无法连接，已保留当前计划。",
            ) from error
        if response.status_code >= 400:
            raise ApiError(
                502,
                "plan_revision_upstream_failed",
                "计划重排服务返回异常，已保留当前计划。",
            )
        try:
            body = response.json()
            content = body["choices"][0]["message"]["content"]
            parsed = json.loads(content)
            usage = body.get("usage") or {}
            parsed["provider"] = "deepseek"
            parsed["model"] = self._settings.deepseek_model
            parsed["input_tokens"] = _optional_int(usage.get("prompt_tokens"))
            parsed["output_tokens"] = _optional_int(
                usage.get("completion_tokens"),
            )
            parsed["prompt_cache_hit_tokens"] = _optional_int(
                usage.get("prompt_cache_hit_tokens"),
            )
            parsed["prompt_cache_miss_tokens"] = _optional_int(
                usage.get("prompt_cache_miss_tokens"),
            )
            return PlanRevisionModelResult.model_validate(parsed)
        except (KeyError, TypeError, ValueError, ValidationError) as error:
            raise ApiError(
                502,
                "plan_revision_invalid",
                "计划重排格式无效，已保留当前计划。",
            ) from error


class PlanRevisionService:
    """生成待确认重排产物，不直接修改正式计划。"""

    def __init__(
        self,
        *,
        session: Session,
        settings: Settings,
        client: PlanRevisionClient,
        response_cache: AiResponseCache | None = None,
    ) -> None:
        self._session = session
        self._settings = settings
        self._client = client
        self._response_cache = response_cache

    async def generate(
        self,
        user_id: UUID,
        request: PlanRevisionRequest,
        *,
        request_id: str | None = None,
    ) -> tuple[AiArtifact, bool]:
        started_at = time.perf_counter()
        if not self._settings.plan_revision_enabled:
            raise ApiError(
                503,
                "plan_revision_unavailable",
                "周期重排功能暂时关闭，当前计划不会改变。",
            )
        digest = _request_digest(request, self._settings.deepseek_model)
        if not request.force:
            cached = self._find_cached(user_id, digest)
            if cached is not None:
                self._record_usage(
                    provider=cached.provider,
                    model=cached.model,
                    input_tokens=0,
                    output_tokens=0,
                    latency_ms=_elapsed_ms(started_at),
                    result_code="cached",
                    request_id=request_id,
                )
                return cached, True
        mode = "cloud_adaptation"
        app_cache_hit = False
        try:
            if self._response_cache is None or request.force:
                result = await self._client.generate(request)
            else:
                cache_key = build_ai_response_cache_key(
                    capability="plan_revision",
                    model=self._settings.deepseek_model,
                    prompt_contract_version=PLAN_REVISION_PROMPT_CONTRACT,
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
            result = _local_safe_fallback(request)
            mode = "local_safe_fallback"
        _validate_result(request, result)
        artifact = self._persist(user_id, request, digest, result, mode)
        self._record_usage(
            provider=result.provider,
            model=result.model or self._settings.deepseek_model,
            input_tokens=result.input_tokens,
            output_tokens=result.output_tokens,
            prompt_cache_hit_tokens=result.prompt_cache_hit_tokens,
            prompt_cache_miss_tokens=result.prompt_cache_miss_tokens,
            latency_ms=_elapsed_ms(started_at),
            result_code="cached" if app_cache_hit else mode,
            request_id=request_id,
        )
        return artifact, app_cache_hit

    def _find_cached(self, user_id: UUID, digest: str) -> AiArtifact | None:
        cutoff = utc_now() - timedelta(minutes=10)
        return self._session.scalar(
            select(AiArtifact)
            .where(
                AiArtifact.user_id == user_id,
                AiArtifact.artifact_type == PLAN_REVISION_ARTIFACT_TYPE,
                AiArtifact.context_digest == digest,
                AiArtifact.generated_at >= cutoff,
                AiArtifact.decision_status == "pending",
            )
            .order_by(AiArtifact.generated_at.desc())
            .limit(1),
        )

    def _persist(
        self,
        user_id: UUID,
        request: PlanRevisionRequest,
        digest: str,
        result: PlanRevisionModelResult,
        mode: str,
    ) -> AiArtifact:
        model = result.model or (
            "deterministic-plan-revision-v1"
            if mode == "local_safe_fallback"
            else self._settings.deepseek_model
        )
        job = AiGenerationJob(
            user_id=user_id,
            capability="trainer",
            artifact_type=PLAN_REVISION_ARTIFACT_TYPE,
            provider=result.provider,
            model=model,
            context_digest=digest,
            state="completed",
            completed_at=utc_now(),
        )
        self._session.add(job)
        self._session.flush()
        artifact = AiArtifact(
            job_id=job.id,
            user_id=user_id,
            capability="trainer",
            artifact_type=PLAN_REVISION_ARTIFACT_TYPE,
            schema_version=1,
            decision_status="pending",
            context_digest=digest,
            payload={
                "proposal_status": "pending",
                "client_context_digest": request.client_context_digest,
                "remaining_dates": [
                    value.isoformat() for value in request.remaining_dates
                ],
                "revised_prescription": result.revised_prescription.model_dump(
                    mode="json",
                ),
                "differences": [
                    item.model_dump(mode="json") for item in result.differences
                ],
                "generation_meta": {
                    "prompt_contract_version": PLAN_REVISION_PROMPT_CONTRACT,
                    "generation_mode": mode,
                    "app_cache_hit": False,
                    "model": model,
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
            provider=result.provider,
            model=model,
        )
        self._session.add(artifact)
        self._session.commit()
        self._session.refresh(artifact)
        return artifact

    def _record_usage(self, **metrics: Any) -> None:
        AiUsageRecorder(self._session).record(
            capability="plan_revision",
            prompt_contract_version=PLAN_REVISION_PROMPT_CONTRACT,
            **metrics,
        )


def _local_safe_fallback(
    request: PlanRevisionRequest,
) -> PlanRevisionModelResult:
    sessions = request.current_prescription.weekly_sessions
    revised = []
    differences = []
    for index, session in enumerate(sessions):
        next_duration = min(session.duration_minutes, request.available_minutes)
        if (
            "no_increase" in request.safety_constraint_codes
            or request.completion_summary.missed_sessions >= 2
        ):
            next_duration = max(20, round(next_duration * 0.8))
        revised_session = session.model_copy(
            update={"duration_minutes": next_duration},
        )
        revised.append(revised_session)
        if next_duration != session.duration_minutes:
            differences.append(
                PlanRevisionDiff(
                    session_index=index,
                    before_training_type=session.training_type,
                    after_training_type=session.training_type,
                    before_duration_minutes=session.duration_minutes,
                    after_duration_minutes=next_duration,
                    reason_code="local_safe_fallback",
                ),
            )
    if not differences:
        first = sessions[0]
        differences.append(
            PlanRevisionDiff(
                session_index=0,
                before_training_type=first.training_type,
                after_training_type=first.training_type,
                before_duration_minutes=first.duration_minutes,
                after_duration_minutes=first.duration_minutes,
                reason_code="local_safe_fallback",
            ),
        )
    return PlanRevisionModelResult(
        revised_prescription=request.current_prescription.model_copy(
            update={"weekly_sessions": revised},
        ),
        differences=differences,
        provider="local",
        model="deterministic-plan-revision-v1",
        input_tokens=0,
        output_tokens=0,
        prompt_cache_hit_tokens=0,
        prompt_cache_miss_tokens=0,
    )


def _validate_result(
    request: PlanRevisionRequest,
    result: PlanRevisionModelResult,
) -> None:
    before = request.current_prescription.weekly_sessions
    after = result.revised_prescription.weekly_sessions
    if len(after) != len(before):
        raise ApiError(
            422,
            "plan_revision_unsafe",
            "重排结果改变了课程数量，已保留当前计划。",
        )
    for index, session in enumerate(after):
        if session.duration_minutes > request.available_minutes:
            raise ApiError(
                422,
                "plan_revision_unsafe",
                "重排结果超过可用训练时间，已保留当前计划。",
            )
        if "no_increase" in request.safety_constraint_codes:
            previous = before[index]
            if session.duration_minutes > previous.duration_minutes:
                raise ApiError(
                    422,
                    "plan_revision_unsafe",
                    "重排结果违反禁止加量约束，已保留当前计划。",
                )
    for item in result.differences:
        if item.session_index >= len(before):
            raise ApiError(
                422,
                "plan_revision_unsafe",
                "重排差异索引无效，已保留当前计划。",
            )
        previous = before[item.session_index]
        revised = after[item.session_index]
        if (
            item.before_training_type != previous.training_type
            or item.before_duration_minutes != previous.duration_minutes
            or item.after_training_type != revised.training_type
            or item.after_duration_minutes != revised.duration_minutes
        ):
            raise ApiError(
                422,
                "plan_revision_unsafe",
                "重排差异与处方正文不一致，已保留当前计划。",
            )
    changed_indices = {
        index
        for index, (previous, revised) in enumerate(zip(before, after, strict=True))
        if previous != revised
    }
    difference_indices = {item.session_index for item in result.differences}
    if len(difference_indices) != len(result.differences) or (
        changed_indices and difference_indices != changed_indices
    ):
        raise ApiError(
            422,
            "plan_revision_unsafe",
            "重排差异未完整描述处方变化，已保留当前计划。",
        )


def _request_digest(request: PlanRevisionRequest, model: str) -> str:
    canonical = json.dumps(
        {
            "capability": "plan_revision",
            "model": model,
            "prompt_contract_version": PLAN_REVISION_PROMPT_CONTRACT,
            "request": request.model_dump(mode="json", exclude={"force"}),
        },
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    )
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def _result_to_cache(result: PlanRevisionModelResult) -> dict[str, object]:
    return {
        "revised_prescription": result.revised_prescription.model_dump(
            mode="json",
        ),
        "differences": [
            item.model_dump(mode="json") for item in result.differences
        ],
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
) -> PlanRevisionModelResult:
    result = PlanRevisionModelResult.model_validate(payload)
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


def _optional_int(value: Any) -> int | None:
    return value if isinstance(value, int) and value >= 0 else None


def _elapsed_ms(started_at: float) -> int:
    return max(0, round((time.perf_counter() - started_at) * 1000))
