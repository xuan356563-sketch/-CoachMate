from __future__ import annotations

import asyncio
import hashlib
import json
import time
import warnings
from dataclasses import dataclass
from io import BytesIO
from typing import Any, Literal, Protocol
from uuid import UUID

import httpx
from PIL import Image, ImageOps, UnidentifiedImageError
from pydantic import BaseModel, ConfigDict, Field, ValidationError, field_validator
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import Settings
from app.core.errors import ApiError
from app.core.security import utc_now
from app.models.ai import AiArtifact, AiGenerationJob
from app.services.ai_usage import AiUsageRecorder
from app.services.knowledge_catalog import (
    KNOWLEDGE_CATALOG_VERSION,
    KnowledgeCatalogService,
)
from app.services.prompt_budget import GENERIC_TEXT_PROMPT_POLICY
from app.services.race_recognition import detect_image_mime_type
from app.services.training_skills import SkillBundleError, TrainingSkillRegistry

AiTextCapability = Literal["trainer", "recovery"]
AiArtifactDecision = Literal["accepted", "rejected"]
AI_TEXT_PROMPT_CONTRACT = "ai-text-v2"
AI_MOTION_PROMPT_CONTRACT = "ai-motion-v1"


class AiGenerationContext(BaseModel):
    """文本能力的最小非健康训练上下文。"""

    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    goal: str = Field(default="保持稳定训练", max_length=120)
    sports: list[str] = Field(default_factory=list, max_length=4)
    available_minutes: int = Field(default=30, ge=0, le=360)
    scheduled_minutes: int | None = Field(default=None, ge=0, le=360)
    scheduled_period: str | None = Field(default=None, max_length=32)

    @field_validator("sports")
    @classmethod
    def normalize_sports(cls, values: list[str]) -> list[str]:
        return [value.strip()[:32] for value in values if value.strip()][:4]


class AiTextGenerationRequest(BaseModel):
    """训练计划和恢复建议的客户端请求，不保存原始文本。"""

    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    capability: AiTextCapability
    prompt: str = Field(default="", max_length=600)
    context: AiGenerationContext
    force: bool = False


class TrainerWorkoutCard(BaseModel):
    """训练计划中的稳定卡片字段。"""

    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    title: str = Field(min_length=1, max_length=80)
    duration_minutes: int = Field(ge=10, le=180)
    intensity: str = Field(min_length=1, max_length=40)
    focus: list[str] = Field(min_length=1, max_length=4)
    safety_note: str = Field(min_length=1, max_length=160)

    @field_validator("focus")
    @classmethod
    def normalize_focus(cls, values: list[str]) -> list[str]:
        return [value.strip()[:80] for value in values if value.strip()][:4]


class TrainerPlanPayload(BaseModel):
    """AI Trainer 的受控计划输出。"""

    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    cycle_label: str = Field(min_length=1, max_length=80)
    weekly_structure: str = Field(min_length=1, max_length=240)
    workout_cards: list[TrainerWorkoutCard] = Field(min_length=1, max_length=7)
    safety_notes: list[str] = Field(min_length=1, max_length=4)

    @field_validator("safety_notes")
    @classmethod
    def normalize_safety_notes(cls, values: list[str]) -> list[str]:
        return [value.strip()[:160] for value in values if value.strip()][:4]


class RecoveryDashboardPayload(BaseModel):
    """AI Recovery 的受控恢复仪表盘输出。"""

    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    readiness_score: int = Field(ge=0, le=100)
    recommended_action: str = Field(min_length=1, max_length=160)
    factors: list[str] = Field(min_length=1, max_length=5)
    today_tasks: list[str] = Field(min_length=1, max_length=5)
    red_flags: list[str] = Field(default_factory=list, max_length=4)
    safety_note: str = Field(min_length=1, max_length=180)

    @field_validator("factors", "today_tasks", "red_flags")
    @classmethod
    def normalize_items(cls, values: list[str]) -> list[str]:
        return [value.strip()[:160] for value in values if value.strip()]


class MotionScorePayload(BaseModel):
    """AI Motion 的受控评分输出。"""

    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    score: int = Field(ge=0, le=100)
    risk_level: Literal["low", "medium", "high"]
    confidence: float = Field(ge=0, le=1)
    detected_errors: list[str] = Field(default_factory=list, max_length=4)
    corrections: list[str] = Field(min_length=1, max_length=4)
    replacements: list[str] = Field(default_factory=list, max_length=4)
    safety_note: str = Field(min_length=1, max_length=180)

    @field_validator("detected_errors", "corrections", "replacements")
    @classmethod
    def normalize_motion_items(cls, values: list[str]) -> list[str]:
        return [value.strip()[:160] for value in values if value.strip()]


class _TextModelOutput(BaseModel):
    """DeepSeek 返回的内部 JSON 包装，不向客户端透传。"""

    model_config = ConfigDict(extra="forbid")

    payload: dict[str, Any]
    warnings: list[str] = Field(default_factory=list, max_length=4)

    @field_validator("warnings")
    @classmethod
    def normalize_warnings(cls, values: list[str]) -> list[str]:
        return [value.strip()[:160] for value in values if value.strip()]


class _MotionModelOutput(_TextModelOutput):
    """MiniMax 的动作图片输出额外声明敏感内容状态。"""

    sensitive_content: bool = False


@dataclass(frozen=True)
class GeneratedAiArtifact:
    """已验证、可安全持久化和传给 Flutter 的 AI 产物。"""

    capability: str
    artifact_type: str
    schema_version: int
    payload: dict[str, object]
    warnings: list[str]
    provider: str
    model: str
    input_tokens: int | None = None
    output_tokens: int | None = None
    prompt_cache_hit_tokens: int | None = None
    prompt_cache_miss_tokens: int | None = None


class TextGenerationClient(Protocol):
    async def generate(
        self,
        request: AiTextGenerationRequest,
    ) -> GeneratedAiArtifact:
        """生成并校验文本能力产物。"""


class MotionGenerationClient(Protocol):
    async def generate(
        self,
        *,
        image: bytes,
        rule_id: str,
        local_pose_summary: str,
    ) -> GeneratedAiArtifact:
        """生成并校验动作图片能力产物。"""


class HttpDeepSeekClient:
    """DeepSeek JSON Mode 适配器，只返回通过本地 Schema 的结果。"""

    def __init__(
        self,
        settings: Settings,
        transport: httpx.AsyncBaseTransport | None = None,
    ) -> None:
        self._settings = settings
        self._transport = transport

    async def generate(
        self,
        request: AiTextGenerationRequest,
    ) -> GeneratedAiArtifact:
        api_key = self._settings.deepseek_api_key
        if api_key is None or not api_key.get_secret_value().strip():
            raise ApiError(503, "deepseek_not_configured", "AI 服务尚未配置")

        system_prompt = _deepseek_system_prompt(request.capability)
        user_prompt = _deepseek_user_prompt(request)
        GENERIC_TEXT_PROMPT_POLICY.validate_required_parts(
            system_prompt,
            user_prompt,
        )
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
            "max_tokens": GENERIC_TEXT_PROMPT_POLICY.max_output_tokens,
            "response_format": {"type": "json_object"},
        }
        headers = {
            "Authorization": f"Bearer {api_key.get_secret_value()}",
            "Content-Type": "application/json",
        }
        endpoint = f"{self._settings.deepseek_base_url.rstrip('/')}/chat/completions"

        try:
            async with asyncio.timeout(self._settings.ai_generation_timeout_seconds):
                async with httpx.AsyncClient(
                    timeout=httpx.Timeout(self._settings.ai_generation_timeout_seconds),
                    transport=self._transport,
                ) as client:
                    response = await self._post_with_retry(
                        client,
                        endpoint,
                        headers,
                        payload,
                    )
        except (TimeoutError, httpx.TimeoutException) as error:
            raise ApiError(
                504,
                "deepseek_timeout",
                "AI 生成超时，请稍后重试",
            ) from error

        try:
            body = response.json()
            content = body["choices"][0]["message"]["content"]
            if not isinstance(content, str):
                raise TypeError
            output = _TextModelOutput.model_validate(json.loads(content))
            input_tokens, output_tokens = _usage_tokens(body)
            cache_hit_tokens, cache_miss_tokens = _prompt_cache_tokens(body)
            return _validated_text_artifact(
                request.capability,
                output.payload,
                output.warnings,
                model=self._settings.deepseek_model,
                input_tokens=input_tokens,
                output_tokens=output_tokens,
                prompt_cache_hit_tokens=cache_hit_tokens,
                prompt_cache_miss_tokens=cache_miss_tokens,
            )
        except (KeyError, IndexError, TypeError, ValueError, ValidationError) as error:
            raise ApiError(
                502,
                "deepseek_invalid_output",
                "AI 返回了无法使用的训练建议，请重试或使用本地规则。",
            ) from error

    async def _post_with_retry(
        self,
        client: httpx.AsyncClient,
        endpoint: str,
        headers: dict[str, str],
        payload: dict[str, object],
    ) -> httpx.Response:
        for attempt in range(2):
            try:
                response = await client.post(endpoint, headers=headers, json=payload)
            except httpx.TimeoutException:
                raise
            except httpx.RequestError as error:
                if attempt == 0:
                    await asyncio.sleep(0)
                    continue
                raise ApiError(
                    502,
                    "deepseek_connection_failed",
                    "AI 服务暂时无法连接，请稍后重试",
                ) from error

            if response.status_code >= 500 and attempt == 0:
                continue
            if response.status_code == 429:
                raise ApiError(429, "deepseek_rate_limited", "AI 服务繁忙，请稍后重试")
            if response.status_code >= 400:
                raise ApiError(502, "deepseek_upstream_failed", "AI 服务返回异常")
            return response

        raise ApiError(502, "deepseek_upstream_failed", "AI 服务返回异常")


class HttpMiniMaxMotionClient:
    """MiniMax-M3 图片动作分析适配器，图片始终使用内存中的去元数据副本。"""

    def __init__(
        self,
        settings: Settings,
        transport: httpx.AsyncBaseTransport | None = None,
    ) -> None:
        self._settings = settings
        self._transport = transport

    async def generate(
        self,
        *,
        image: bytes,
        rule_id: str,
        local_pose_summary: str,
    ) -> GeneratedAiArtifact:
        api_key = self._settings.minimax_api_key
        if api_key is None or not api_key.get_secret_value().strip():
            raise ApiError(503, "minimax_not_configured", "动作图片 AI 尚未配置")
        clean_image, mime_type = _sanitize_motion_image(image)
        data_url = f"data:{mime_type};base64,{_base64(clean_image)}"
        payload = {
            "model": self._settings.minimax_model,
            "messages": [
                {
                    "role": "user",
                    "content": [
                        {
                            "type": "text",
                            "text": _motion_prompt(rule_id, local_pose_summary),
                        },
                        {
                            "type": "image_url",
                            "image_url": {"url": data_url},
                        },
                    ],
                },
            ],
            "temperature": 0,
            "max_completion_tokens": 700,
            "thinking": {"type": "disabled"},
        }
        headers = {
            "Authorization": f"Bearer {api_key.get_secret_value()}",
            "Content-Type": "application/json",
        }
        endpoint = f"{self._settings.minimax_base_url.rstrip('/')}/v1/chat/completions"
        try:
            async with asyncio.timeout(self._settings.minimax_timeout_seconds):
                async with httpx.AsyncClient(
                    timeout=httpx.Timeout(self._settings.minimax_timeout_seconds),
                    transport=self._transport,
                ) as client:
                    response = await self._post_with_retry(
                        client,
                        endpoint,
                        headers,
                        payload,
                    )
        except (TimeoutError, httpx.TimeoutException) as error:
            raise ApiError(
                504,
                "minimax_timeout",
                "动作图片分析超时，请稍后重试",
            ) from error

        try:
            body = response.json()
            content = body["choices"][0]["message"]["content"]
            if not isinstance(content, str):
                raise TypeError
            output = _MotionModelOutput.model_validate(json.loads(content))
            if output.sensitive_content:
                raise ApiError(
                    422,
                    "motion_image_content_unsupported",
                    "该图片不适合用于动作分析",
                )
            payload = MotionScorePayload.model_validate(output.payload).model_dump(
                mode="json",
            )
            input_tokens, output_tokens = _usage_tokens(body)
            return GeneratedAiArtifact(
                capability="motion",
                artifact_type="motion_score_v1",
                schema_version=1,
                payload=payload,
                warnings=output.warnings,
                provider="minimax",
                model=self._settings.minimax_model,
                input_tokens=input_tokens,
                output_tokens=output_tokens,
            )
        except ApiError:
            raise
        except (KeyError, IndexError, TypeError, ValueError, ValidationError) as error:
            raise ApiError(
                502,
                "minimax_invalid_output",
                "动作图片分析结果无法解析，请换一张清晰照片重试",
            ) from error

    async def _post_with_retry(
        self,
        client: httpx.AsyncClient,
        endpoint: str,
        headers: dict[str, str],
        payload: dict[str, object],
    ) -> httpx.Response:
        for attempt in range(2):
            try:
                response = await client.post(endpoint, headers=headers, json=payload)
            except httpx.TimeoutException:
                raise
            except httpx.RequestError as error:
                if attempt == 0:
                    await asyncio.sleep(0)
                    continue
                raise ApiError(
                    502,
                    "minimax_connection_failed",
                    "动作图片 AI 暂时无法连接",
                ) from error
            if response.status_code >= 500 and attempt == 0:
                continue
            if response.status_code == 429:
                raise ApiError(429, "minimax_rate_limited", "动作图片 AI 服务繁忙")
            if response.status_code >= 400:
                raise ApiError(
                    502,
                    "minimax_upstream_failed",
                    "动作图片 AI 服务返回异常",
                )
            return response
        raise ApiError(502, "minimax_upstream_failed", "动作图片 AI 服务返回异常")


class AiArtifactService:
    """编排、校验和持久化 AI 产物；所有原始输入只在请求内存中存在。"""

    def __init__(
        self,
        session: Session,
        settings: Settings,
        text_client: TextGenerationClient,
        motion_client: MotionGenerationClient,
        training_skill_registry: TrainingSkillRegistry | None = None,
    ) -> None:
        self._session = session
        self._settings = settings
        self._text_client = text_client
        self._motion_client = motion_client
        self._training_skill_registry = training_skill_registry

    async def generate_text(
        self,
        user_id: UUID,
        request: AiTextGenerationRequest,
        *,
        request_id: str | None = None,
    ) -> AiArtifact:
        started_at = time.perf_counter()
        digest = _text_context_digest(request)
        if not request.force:
            existing = self._find_cached(user_id, request.capability, digest)
            if existing is not None:
                self._record_usage(
                    provider="deepseek",
                    model=self._settings.deepseek_model,
                    capability=request.capability,
                    prompt_contract_version=AI_TEXT_PROMPT_CONTRACT,
                    input_tokens=0,
                    output_tokens=0,
                    latency_ms=_elapsed_ms(started_at),
                    result_code="cached",
                    request_id=request_id,
                )
                return existing
        artifact_type = _artifact_type_for(request.capability)
        job = self._create_job(
            user_id=user_id,
            capability=request.capability,
            artifact_type=artifact_type,
            provider="deepseek",
            model=self._settings.deepseek_model,
            context_digest=digest,
        )
        try:
            generated = await self._text_client.generate(request)
        except ApiError as error:
            self._mark_failed(job, error.code)
            self._record_usage(
                provider="deepseek",
                model=self._settings.deepseek_model,
                capability=request.capability,
                prompt_contract_version=AI_TEXT_PROMPT_CONTRACT,
                input_tokens=None,
                output_tokens=None,
                latency_ms=_elapsed_ms(started_at),
                result_code=error.code,
                request_id=request_id,
            )
            raise
        artifact = self._complete_job(job, user_id, digest, generated)
        self._record_usage(
            provider=generated.provider,
            model=generated.model,
            capability=request.capability,
            prompt_contract_version=AI_TEXT_PROMPT_CONTRACT,
            input_tokens=generated.input_tokens,
            output_tokens=generated.output_tokens,
            prompt_cache_hit_tokens=generated.prompt_cache_hit_tokens,
            prompt_cache_miss_tokens=generated.prompt_cache_miss_tokens,
            latency_ms=_elapsed_ms(started_at),
            result_code="generated",
            request_id=request_id,
        )
        return artifact

    async def generate_motion(
        self,
        user_id: UUID,
        *,
        image: bytes,
        rule_id: str,
        local_pose_summary: str,
        request_id: str | None = None,
    ) -> AiArtifact:
        started_at = time.perf_counter()
        if not rule_id.strip() or len(rule_id) > 64:
            raise ApiError(422, "motion_rule_invalid", "请选择有效的动作类型")
        clean_image, _ = _sanitize_motion_image(image)
        digest = hashlib.sha256(
            f"motion:{rule_id}:{hashlib.sha256(clean_image).hexdigest()}".encode(
                "utf-8",
            ),
        ).hexdigest()
        job = self._create_job(
            user_id=user_id,
            capability="motion",
            artifact_type="motion_score_v1",
            provider="minimax",
            model=self._settings.minimax_model,
            context_digest=digest,
        )
        try:
            generated = await self._motion_client.generate(
                image=clean_image,
                rule_id=rule_id.strip(),
                local_pose_summary=local_pose_summary[:500],
            )
        except ApiError as error:
            self._mark_failed(job, error.code)
            self._record_usage(
                provider="minimax",
                model=self._settings.minimax_model,
                capability="motion",
                prompt_contract_version=AI_MOTION_PROMPT_CONTRACT,
                input_tokens=None,
                output_tokens=None,
                latency_ms=_elapsed_ms(started_at),
                result_code=error.code,
                request_id=request_id,
            )
            raise
        artifact = self._complete_job(job, user_id, digest, generated)
        self._record_usage(
            provider=generated.provider,
            model=generated.model,
            capability="motion",
            prompt_contract_version=AI_MOTION_PROMPT_CONTRACT,
            input_tokens=generated.input_tokens,
            output_tokens=generated.output_tokens,
            latency_ms=_elapsed_ms(started_at),
            result_code="generated",
            request_id=request_id,
        )
        return artifact

    def list_artifacts(
        self,
        user_id: UUID,
        capability: str | None = None,
    ) -> list[AiArtifact]:
        statement = select(AiArtifact).where(AiArtifact.user_id == user_id)
        if capability is not None:
            statement = statement.where(AiArtifact.capability == capability)
        statement = statement.order_by(AiArtifact.generated_at.desc()).limit(50)
        return list(self._session.execute(statement).scalars())

    def decide(
        self,
        user_id: UUID,
        artifact_id: UUID,
        decision: AiArtifactDecision,
    ) -> AiArtifact:
        artifact = self._session.get(AiArtifact, artifact_id)
        if artifact is None or artifact.user_id != user_id:
            raise ApiError(404, "ai_artifact_not_found", "未找到对应的 AI 结果")
        if artifact.artifact_type in {
            "training_prescription_v1",
            "training_prescription_v2",
            "plan_revision_v1",
        }:
            if artifact.decision_status != "pending":
                if artifact.decision_status != decision:
                    if artifact.artifact_type == "plan_revision_v1":
                        raise ApiError(
                            409,
                            "plan_revision_decision_conflict",
                            "周期重排已完成确认或拒绝，不能更改最终决定。",
                        )
                    raise ApiError(
                        409,
                        "training_prescription_decision_conflict",
                        "训练处方已完成确认或拒绝，不能更改最终决定。",
                    )
                if decision == "accepted" and artifact.artifact_type.startswith(
                    "training_prescription_",
                ):
                    self._validate_training_prescription_acceptance(artifact)
                return artifact
            if decision == "accepted" and artifact.artifact_type.startswith(
                "training_prescription_",
            ):
                self._validate_training_prescription_acceptance(artifact)
        artifact.decision_status = decision
        artifact.decided_at = utc_now()
        self._session.commit()
        self._session.refresh(artifact)
        return artifact

    def delete(self, user_id: UUID, artifact_id: UUID) -> None:
        artifact = self._session.get(AiArtifact, artifact_id)
        if artifact is None or artifact.user_id != user_id:
            raise ApiError(404, "ai_artifact_not_found", "未找到对应的 AI 结果")
        self._session.delete(artifact)
        self._session.commit()

    def _validate_training_prescription_acceptance(
        self,
        artifact: AiArtifact,
    ) -> None:
        if self._settings.training_plan_kill_switch:
            raise _training_skill_unavailable()
        registry = self._training_skill_registry or TrainingSkillRegistry.default()
        payload = artifact.payload
        applied = payload.get("applied_skill")
        reason_code = payload.get("selection_reason_code")
        if not isinstance(applied, dict) or not isinstance(reason_code, str):
            raise _training_skill_unavailable()
        coverage = applied.get("coverage")
        if not isinstance(coverage, str):
            raise _training_skill_unavailable()
        try:
            selection = registry.resolve(coverage)
        except SkillBundleError as error:
            raise _training_skill_unavailable() from error
        expected = {
            "id": selection.manifest.id,
            "version": selection.manifest.version,
            "display_name": selection.manifest.display_name,
            "source_sha256": selection.source_sha256,
            "runtime_sha256": selection.runtime_sha256,
            "fragment_sha256": selection.fragment_sha256,
            "coverage": selection.coverage,
        }
        if any(applied.get(key) != value for key, value in expected.items()):
            raise _training_skill_unavailable()
        if reason_code != selection.selection_reason_code:
            raise _training_skill_unavailable()
        if artifact.artifact_type == "training_prescription_v2":
            self._validate_training_prescription_v2_knowledge(artifact)

    def _validate_training_prescription_v2_knowledge(
        self,
        artifact: AiArtifact,
    ) -> None:
        # 延迟导入以避免训练处方客户端与通用 AI 产物服务形成模块循环。
        from app.services.training_prescription import ValidatedTrainingPrescription

        if artifact.schema_version != 2:
            raise _training_skill_unavailable()
        payload = artifact.payload
        generation_meta = payload.get("generation_meta")
        population_template_id = payload.get("population_template_id")
        citations = payload.get("knowledge_citations")
        if (
            not isinstance(generation_meta, dict)
            or generation_meta.get("contract_version") != 2
            or generation_meta.get("knowledge_snapshot_version")
            != KNOWLEDGE_CATALOG_VERSION
            or generation_meta.get("generation_mode")
            not in {
                "local_template",
                "cloud_adaptation",
                "local_safe_fallback",
            }
            or not isinstance(population_template_id, str)
            or not isinstance(citations, list)
            or len(citations) > 5
        ):
            raise _training_skill_unavailable()

        catalog = KnowledgeCatalogService(self._session).catalog()
        population_ids = {
            item.id
            for item in catalog.population_templates
            if item.automatic_plan_allowed
        }
        principle_ids = {item.id for item in catalog.principles}
        template_by_id = {
            item.id: item
            for item in catalog.training_templates
        }
        if population_template_id not in population_ids:
            raise _training_skill_unavailable()
        for citation in citations:
            if not isinstance(citation, dict):
                raise _training_skill_unavailable()
            citation_id = citation.get("id")
            citation_type = citation.get("type")
            if citation_type == "principle":
                if citation_id not in principle_ids:
                    raise _training_skill_unavailable()
            elif citation_type == "training_template":
                template = template_by_id.get(citation_id)
                if (
                    template is None
                    or template.population_template_id
                    != population_template_id
                ):
                    raise _training_skill_unavailable()
            else:
                raise _training_skill_unavailable()
        try:
            ValidatedTrainingPrescription.model_validate(
                {
                    "cycle_focus": payload.get("cycle_focus"),
                    "weekly_sessions": payload.get("weekly_sessions"),
                    "progression_mode": payload.get("progression_mode"),
                },
            )
        except ValidationError as error:
            raise _training_skill_unavailable() from error

    def _find_cached(
        self,
        user_id: UUID,
        capability: str,
        context_digest: str,
    ) -> AiArtifact | None:
        statement = (
            select(AiArtifact)
            .where(
                AiArtifact.user_id == user_id,
                AiArtifact.capability == capability,
                AiArtifact.context_digest == context_digest,
                AiArtifact.decision_status == "pending",
            )
            .order_by(AiArtifact.generated_at.desc())
            .limit(1)
        )
        return self._session.execute(statement).scalar_one_or_none()

    def _create_job(
        self,
        *,
        user_id: UUID,
        capability: str,
        artifact_type: str,
        provider: str,
        model: str,
        context_digest: str,
    ) -> AiGenerationJob:
        job = AiGenerationJob(
            user_id=user_id,
            capability=capability,
            artifact_type=artifact_type,
            provider=provider,
            model=model,
            context_digest=context_digest,
            state="processing",
        )
        self._session.add(job)
        self._session.flush()
        return job

    def _mark_failed(self, job: AiGenerationJob, error_code: str) -> None:
        job.state = "failed"
        job.error_code = error_code
        job.completed_at = utc_now()
        self._session.commit()

    def _complete_job(
        self,
        job: AiGenerationJob,
        user_id: UUID,
        context_digest: str,
        generated: GeneratedAiArtifact,
    ) -> AiArtifact:
        artifact = AiArtifact(
            job_id=job.id,
            user_id=user_id,
            capability=generated.capability,
            artifact_type=generated.artifact_type,
            schema_version=generated.schema_version,
            decision_status="pending",
            context_digest=context_digest,
            payload=generated.payload,
            warnings=generated.warnings,
            provider=generated.provider,
            model=generated.model,
        )
        job.state = "completed"
        job.completed_at = utc_now()
        self._session.add(artifact)
        self._session.commit()
        self._session.refresh(artifact)
        return artifact

    def _record_usage(
        self,
        *,
        provider: str,
        model: str,
        capability: str | None,
        prompt_contract_version: str | None,
        input_tokens: int | None,
        output_tokens: int | None,
        latency_ms: int,
        result_code: str,
        request_id: str | None,
        prompt_cache_hit_tokens: int | None = None,
        prompt_cache_miss_tokens: int | None = None,
    ) -> None:
        AiUsageRecorder(self._session).record(
            provider=provider,
            model=model,
            capability=capability,
            prompt_contract_version=prompt_contract_version,
            input_tokens=input_tokens,
            output_tokens=output_tokens,
            prompt_cache_hit_tokens=prompt_cache_hit_tokens,
            prompt_cache_miss_tokens=prompt_cache_miss_tokens,
            latency_ms=latency_ms,
            result_code=result_code,
            request_id=request_id,
        )


def _validated_text_artifact(
    capability: AiTextCapability,
    payload: dict[str, Any],
    warnings: list[str],
    *,
    model: str,
    input_tokens: int | None = None,
    output_tokens: int | None = None,
    prompt_cache_hit_tokens: int | None = None,
    prompt_cache_miss_tokens: int | None = None,
) -> GeneratedAiArtifact:
    if capability == "trainer":
        validated = TrainerPlanPayload.model_validate(payload).model_dump(mode="json")
        artifact_type = "trainer_plan_v1"
    else:
        validated = RecoveryDashboardPayload.model_validate(payload).model_dump(
            mode="json",
        )
        artifact_type = "recovery_dashboard_v1"
    return GeneratedAiArtifact(
        capability=capability,
        artifact_type=artifact_type,
        schema_version=1,
        payload=validated,
        warnings=warnings,
        provider="deepseek",
        model=model,
        input_tokens=input_tokens,
        output_tokens=output_tokens,
        prompt_cache_hit_tokens=prompt_cache_hit_tokens,
        prompt_cache_miss_tokens=prompt_cache_miss_tokens,
    )


def _usage_tokens(body: dict[str, Any]) -> tuple[int | None, int | None]:
    usage = body.get("usage")
    if not isinstance(usage, dict):
        return None, None
    input_tokens = usage.get("prompt_tokens")
    output_tokens = usage.get("completion_tokens")
    return (
        input_tokens if isinstance(input_tokens, int) else None,
        output_tokens if isinstance(output_tokens, int) else None,
    )


def _prompt_cache_tokens(body: dict[str, Any]) -> tuple[int | None, int | None]:
    usage = body.get("usage")
    if not isinstance(usage, dict):
        return None, None
    hit_tokens = usage.get("prompt_cache_hit_tokens")
    miss_tokens = usage.get("prompt_cache_miss_tokens")
    return (
        hit_tokens if isinstance(hit_tokens, int) else None,
        miss_tokens if isinstance(miss_tokens, int) else None,
    )


def _elapsed_ms(started_at: float) -> int:
    return round((time.perf_counter() - started_at) * 1000)


def _training_skill_unavailable() -> ApiError:
    return ApiError(
        503,
        "training_plan_skill_unavailable",
        "训练 Skill 已变更或暂不可用，请重新生成计划。",
    )


def _artifact_type_for(capability: AiTextCapability) -> str:
    return "trainer_plan_v1" if capability == "trainer" else "recovery_dashboard_v1"


def _text_context_digest(request: AiTextGenerationRequest) -> str:
    content = {
        "capability": request.capability,
        "prompt": request.prompt,
        "context": request.context.model_dump(mode="json", exclude_none=True),
    }
    raw = json.dumps(content, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


def _deepseek_system_prompt(capability: AiTextCapability) -> str:
    if capability == "trainer":
        output = (
            '{"payload":{"cycle_label":"","weekly_structure":"",'
            '"workout_cards":[{"title":"","duration_minutes":30,'
            '"intensity":"","focus":[""],"safety_note":""}],'
            '"safety_notes":[""]},"warnings":[]}'
        )
    else:
        output = (
            '{"payload":{"readiness_score":60,"recommended_action":"",'
            '"factors":[""],"today_tasks":[""],"red_flags":[],'
            '"safety_note":""},"warnings":[]}'
        )
    return (
        "你是 TrainFlow 的结构化训练决策引擎，不是聊天机器人。"
        "只基于输入明确给出的训练信息作答，不得猜测疾病、伤病或个人身份。"
        "输入不包含健康、疼痛、准备度或成长数据，不得自行补充这些结论。"
        "不能建议以疼痛换进度，也不能替代医疗建议。"
        "只输出一个合法 JSON 对象，不要 Markdown、解释文字或代码块。"
        f"输出结构必须完全符合：{output}"
    )


def _deepseek_user_prompt(request: AiTextGenerationRequest) -> str:
    context = json.dumps(
        request.context.model_dump(mode="json", exclude_none=True),
        ensure_ascii=False,
        separators=(",", ":"),
    )
    prompt = request.prompt or "无额外补充。"
    return (
        f"能力：{request.capability}\n"
        f"去标识化训练上下文：{context}\n"
        f"用户补充：{prompt}"
    )


def _motion_prompt(rule_id: str, local_pose_summary: str) -> str:
    return (
        "你是 TrainFlow AI Motion 图片分析器。只评估画面中清晰可见的动作，"
        "禁止诊断疾病、猜测身份或根据不清晰画面编造结论。"
        "疼痛、失衡或高风险不确定时必须保守。"
        "仅返回 JSON："
        '{"payload":{"score":0,"risk_level":"low|medium|high",'
        '"confidence":0,"detected_errors":[],"corrections":[""],'
        '"replacements":[],"safety_note":""},"warnings":[],"sensitive_content":false}。'
        f"目标动作规则：{rule_id}。"
        f"设备端摘要：{local_pose_summary or '无'}。"
    )


def _sanitize_motion_image(image: bytes) -> tuple[bytes, str]:
    """在内存中验证、纠正方向并重编码图片，移除 EXIF 和其他可选元数据。"""
    if not image:
        raise ApiError(400, "image_empty", "请选择动作图片")
    if len(image) > 10 * 1024 * 1024:
        raise ApiError(413, "image_too_large", "图片不能超过 10MB")
    if detect_image_mime_type(image) is None:
        raise ApiError(
            415,
            "image_type_unsupported",
            "仅支持 JPEG、PNG、GIF 或 WebP 图片，HEIC 请先转换格式",
        )
    try:
        with warnings.catch_warnings():
            warnings.simplefilter("error", Image.DecompressionBombWarning)
            with Image.open(BytesIO(image)) as source:
                width, height = source.size
                if width <= 0 or height <= 0 or width * height > 25_000_000:
                    raise ApiError(
                        413,
                        "image_dimensions_invalid",
                        "图片尺寸过大，请选择 2500 万像素以内的照片",
                    )
                source.load()
                normalized = ImageOps.exif_transpose(source).copy()
    except ApiError:
        raise
    except (Image.DecompressionBombWarning, Image.DecompressionBombError) as error:
        raise ApiError(
            413,
            "image_dimensions_invalid",
            "图片尺寸过大，请选择 2500 万像素以内的照片",
        ) from error
    except (UnidentifiedImageError, OSError, ValueError) as error:
        raise ApiError(
            415,
            "image_type_unsupported",
            "图片无法读取，请换一张 JPEG、PNG、GIF 或 WebP 图片",
        ) from error

    output = BytesIO()
    if "A" in normalized.getbands():
        normalized.convert("RGBA").save(output, format="PNG", optimize=True)
        return output.getvalue(), "image/png"
    normalized.convert("RGB").save(output, format="JPEG", quality=90, optimize=True)
    return output.getvalue(), "image/jpeg"


def _base64(value: bytes) -> str:
    """延迟导入避免模块初始化中保留任何媒体对象。"""
    import base64

    return base64.b64encode(value).decode("ascii")
