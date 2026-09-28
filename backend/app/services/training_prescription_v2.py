from __future__ import annotations

import hashlib
import json
import time
from datetime import timedelta
from typing import Literal, Protocol
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, ValidationError
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import Settings
from app.core.errors import ApiError
from app.core.security import utc_now
from app.models.ai import AiArtifact, AiGenerationJob
from app.services.ai_response_cache import (
    AiResponseCache,
    build_ai_response_cache_key,
)
from app.services.ai_usage import AiUsageRecorder
from app.services.knowledge_catalog import (
    KNOWLEDGE_CATALOG_VERSION,
    KnowledgeCatalogService,
    KnowledgeRetrievalResult,
)
from app.services.training_prescription import (
    TRAINING_PRESCRIPTION_PROMPT_CONTRACT,
    FocusCode,
    IntensityBandCode,
    TrainingPrescriptionContext,
    TrainingPrescriptionModelResult,
    TrainingPrescriptionRequest,
    TrainingSessionBlueprint,
    TrainingTypeCode,
    ValidatedTrainingPrescription,
    _validate_for_context,
)
from app.services.training_skills import (
    SkillBundleError,
    SkillSelection,
    TrainingSkillRegistry,
)
from app.services.training_sport_providers import ProviderRegistry

PopulationTemplateId = Literal[
    "sedentary_beginner",
    "low_impact_fat_loss",
    "strength_progression",
    "running_entry_or_race",
    "hyrox_hybrid",
    "older_adult_foundation",
    "shift_worker_flexible",
    "return_to_training_guarded",
]
AiGenerationMode = Literal[
    "local_template",
    "cloud_adaptation",
    "local_safe_fallback",
]
TRAINING_PRESCRIPTION_V2_ARTIFACT_TYPE = "training_prescription_v2"
TRAINING_STRUCTURE_POLICY_VERSION = "training-structure-v1"


class AdaptationSignals(BaseModel):
    """仅包含离散化适配信号，不接受原始健康文本。"""

    model_config = ConfigDict(extra="forbid")

    completion_rate_band: Literal["unknown", "low", "medium", "high"]
    load_trend_code: Literal["unknown", "stable", "rising", "falling"]
    recovery_risk_code: Literal["normal", "observe", "advise", "protect"]
    selected_direction_code: Literal[
        "keep_schedule",
        "keep_one_focus",
        "recovery_first",
        "reduce_one_session",
    ] | None = None


class TrainingPrescriptionV2Request(BaseModel):
    """V2 增加已审核人群模板和知识快照，不接受自由文本。"""

    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    contract_version: Literal[2]
    client_context_digest: str = Field(pattern=r"^[0-9a-f]{64}$")
    population_template_id: PopulationTemplateId
    knowledge_snapshot_version: str = Field(min_length=1, max_length=32)
    context: TrainingPrescriptionContext
    adaptation_signals: AdaptationSignals | None = None
    force: bool = False


class KnowledgeAwarePrescriptionClient(Protocol):
    async def generate(
        self,
        request: TrainingPrescriptionRequest,
        selection: SkillSelection,
    ) -> TrainingPrescriptionModelResult:
        """兼容 V1 生成。"""

    async def generate_with_knowledge(
        self,
        request: TrainingPrescriptionRequest,
        selection: SkillSelection,
        retrieval: KnowledgeRetrievalResult,
    ) -> TrainingPrescriptionModelResult:
        """使用服务端检索出的短摘要生成处方。"""


class TrainingPrescriptionV2Service:
    """编排确定性模板、知识引用、云端适配和待确认产物。"""

    def __init__(
        self,
        *,
        session: Session,
        settings: Settings,
        registry: TrainingSkillRegistry,
        client: KnowledgeAwarePrescriptionClient,
        knowledge: KnowledgeCatalogService,
        response_cache: AiResponseCache | None = None,
    ) -> None:
        self._session = session
        self._settings = settings
        self._registry = registry
        self._client = client
        self._knowledge = knowledge
        self._response_cache = response_cache

    async def generate(
        self,
        user_id: UUID,
        request: TrainingPrescriptionV2Request,
        *,
        request_id: str | None = None,
    ) -> tuple[AiArtifact, bool]:
        started_at = time.perf_counter()
        if not self._settings.training_prescription_v2_enabled:
            raise ApiError(
                503,
                "training_prescription_v2_unavailable",
                "V2 训练处方暂时关闭，请使用现有计划生成流程。",
            )
        if self._settings.training_plan_kill_switch:
            raise ApiError(
                503,
                "training_plan_skill_unavailable",
                "AI 训练计划功能暂时关闭，请使用本地规则计划。",
            )
        if request.knowledge_snapshot_version != KNOWLEDGE_CATALOG_VERSION:
            raise ApiError(
                409,
                "knowledge_snapshot_outdated",
                "训练知识目录已更新，请刷新后重新生成计划。",
            )
        if request.population_template_id == "return_to_training_guarded":
            raise ApiError(
                422,
                "population_template_requires_clearance",
                "伤病后重返训练需要先完成筛查并获得人工许可，当前不能自动生成计划。",
            )
        try:
            selection = self._registry.resolve(request.context.primary_sport)
        except SkillBundleError as error:
            raise ApiError(
                503,
                "training_plan_skill_unavailable",
                "当前没有可用的已审核训练 Skill，请使用本地规则计划。",
            ) from error
        self._knowledge.ensure_seeded()
        retrieval = self._knowledge.retrieve(
            goal=request.context.goal,
            primary_sport=request.context.primary_sport,
            population_template_id=request.population_template_id,
            equipment_access=request.context.equipment_access,
            weekly_training_days=request.context.weekly_training_days,
        )
        digest = _v2_digest(
            request,
            selection,
            retrieval,
            self._settings.deepseek_model,
            training_structure_enabled=(self._settings.training_structure_v1_enabled),
        )
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

        local_request = TrainingPrescriptionRequest(
            contract_version=1,
            client_context_digest=request.client_context_digest,
            context=request.context,
            force=request.force,
        )
        app_cache_hit = False
        if retrieval.is_unambiguous and retrieval.training_templates:
            mode: AiGenerationMode = "local_template"
            result = TrainingPrescriptionModelResult(
                prescription=_compile_local_template(request, retrieval),
                input_tokens=0,
                output_tokens=0,
                prompt_cache_hit_tokens=0,
                prompt_cache_miss_tokens=0,
            )
            provider = "local"
            model = "deterministic-template-v1"
        else:
            mode = "cloud_adaptation"
            try:
                if self._response_cache is not None and not request.force:
                    cache_key = build_ai_response_cache_key(
                        capability="training_prescription_v2",
                        model=self._settings.deepseek_model,
                        prompt_contract_version=(TRAINING_PRESCRIPTION_PROMPT_CONTRACT),
                        skill_hash=(
                            f"{selection.source_sha256}:"
                            f"{selection.runtime_sha256}:"
                            f"{selection.fragment_sha256}"
                        ),
                        knowledge_version=retrieval.version,
                        context_digest=digest,
                    )

                    async def generate_for_cache() -> dict[str, object]:
                        generated = await self._generate_cloud(
                            local_request,
                            selection,
                            retrieval,
                        )
                        return _result_to_cache(generated)

                    (
                        cached_result,
                        app_cache_hit,
                    ) = await self._response_cache.get_or_compute(
                        key=cache_key,
                        ttl_seconds=24 * 60 * 60,
                        producer=generate_for_cache,
                    )
                    result = _result_from_cache(
                        cached_result,
                        cache_hit=app_cache_hit,
                    )
                else:
                    result = await self._generate_cloud(
                        local_request,
                        selection,
                        retrieval,
                    )
                provider = "deepseek"
                model = self._settings.deepseek_model
            except (ApiError, ValidationError):
                app_cache_hit = False
                mode = "local_safe_fallback"
                result = TrainingPrescriptionModelResult(
                    prescription=_compile_safe_fallback(
                        request,
                        self._registry.sport_providers,
                    ),
                    input_tokens=0,
                    output_tokens=0,
                    prompt_cache_hit_tokens=0,
                    prompt_cache_miss_tokens=0,
                )
                provider = "local"
                model = "deterministic-safe-fallback-v1"
        _validate_for_context(
            result.prescription,
            request.context,
            self._registry.sport_providers,
        )
        artifact = self._persist_artifact(
            user_id=user_id,
            request=request,
            selection=selection,
            retrieval=retrieval,
            digest=digest,
            result=result,
            mode=mode,
            provider=provider,
            model=model,
        )
        self._record_usage(
            provider=provider,
            model=model,
            input_tokens=result.input_tokens,
            output_tokens=result.output_tokens,
            prompt_cache_hit_tokens=result.prompt_cache_hit_tokens,
            prompt_cache_miss_tokens=result.prompt_cache_miss_tokens,
            latency_ms=_elapsed_ms(started_at),
            result_code="cached" if app_cache_hit else mode,
            request_id=request_id,
        )
        return artifact, app_cache_hit

    async def _generate_cloud(
        self,
        request: TrainingPrescriptionRequest,
        selection: SkillSelection,
        retrieval: KnowledgeRetrievalResult,
    ) -> TrainingPrescriptionModelResult:
        generator = getattr(self._client, "generate_with_knowledge", None)
        if generator is None:
            return await self._client.generate(request, selection)
        return await generator(request, selection, retrieval)

    def _persist_artifact(
        self,
        *,
        user_id: UUID,
        request: TrainingPrescriptionV2Request,
        selection: SkillSelection,
        retrieval: KnowledgeRetrievalResult,
        digest: str,
        result: TrainingPrescriptionModelResult,
        mode: AiGenerationMode,
        provider: str,
        model: str,
    ) -> AiArtifact:
        job = AiGenerationJob(
            user_id=user_id,
            capability="trainer",
            artifact_type=TRAINING_PRESCRIPTION_V2_ARTIFACT_TYPE,
            provider=provider,
            model=model,
            context_digest=digest,
            state="completed",
            completed_at=utc_now(),
        )
        self._session.add(job)
        self._session.flush()
        payload = result.prescription.model_dump(mode="json", by_alias=True)
        if self._settings.training_structure_v1_enabled:
            _backfill_training_structure(payload)
        payload.update(
            {
                "population_template_id": request.population_template_id,
                "applied_skill": {
                    "id": selection.manifest.id,
                    "version": selection.manifest.version,
                    "display_name": selection.manifest.display_name,
                    "source_sha256": selection.source_sha256,
                    "runtime_sha256": selection.runtime_sha256,
                    "fragment_sha256": selection.fragment_sha256,
                    "coverage": selection.coverage,
                },
                "selection_reason": selection.selection_reason,
                "selection_reason_code": selection.selection_reason_code,
                "knowledge_citations": _citations(retrieval),
                "generation_meta": {
                    "contract_version": 2,
                    "client_context_digest": request.client_context_digest,
                    "prompt_contract_version": (TRAINING_PRESCRIPTION_PROMPT_CONTRACT),
                    "knowledge_snapshot_version": retrieval.version,
                    **(
                        {
                            "structure_policy_version": (
                                TRAINING_STRUCTURE_POLICY_VERSION
                            ),
                        }
                        if self._settings.training_structure_v1_enabled
                        else {}
                    ),
                    "generation_mode": mode,
                    "app_cache_hit": False,
                    "cache_hit": False,
                    "model": model,
                    "input_tokens": result.input_tokens,
                    "output_tokens": result.output_tokens,
                    "prompt_cache_hit_tokens": result.prompt_cache_hit_tokens,
                    "prompt_cache_miss_tokens": result.prompt_cache_miss_tokens,
                },
            },
        )
        artifact = AiArtifact(
            job_id=job.id,
            user_id=user_id,
            capability="trainer",
            artifact_type=TRAINING_PRESCRIPTION_V2_ARTIFACT_TYPE,
            schema_version=2,
            decision_status="pending",
            context_digest=digest,
            payload=payload,
            warnings=[],
            provider=provider,
            model=model,
        )
        self._session.add(artifact)
        self._session.commit()
        self._session.refresh(artifact)
        return artifact

    def _find_cached(self, user_id: UUID, digest: str) -> AiArtifact | None:
        cutoff = utc_now() - timedelta(hours=24)
        return self._session.scalar(
            select(AiArtifact)
            .where(
                AiArtifact.user_id == user_id,
                AiArtifact.artifact_type == TRAINING_PRESCRIPTION_V2_ARTIFACT_TYPE,
                AiArtifact.context_digest == digest,
                AiArtifact.decision_status == "pending",
                AiArtifact.generated_at >= cutoff,
            )
            .order_by(AiArtifact.generated_at.desc())
            .limit(1),
        )

    def _record_usage(
        self,
        *,
        provider: str,
        model: str,
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
            capability="training_prescription_v2",
            prompt_contract_version=TRAINING_PRESCRIPTION_PROMPT_CONTRACT,
            input_tokens=input_tokens,
            output_tokens=output_tokens,
            prompt_cache_hit_tokens=prompt_cache_hit_tokens,
            prompt_cache_miss_tokens=prompt_cache_miss_tokens,
            latency_ms=latency_ms,
            result_code=result_code,
            request_id=request_id,
        )


def _compile_local_template(
    request: TrainingPrescriptionV2Request,
    retrieval: KnowledgeRetrievalResult,
) -> ValidatedTrainingPrescription:
    template = retrieval.training_templates[0]
    sessions = [
        TrainingSessionBlueprint(
            training_type=training_type,
            duration_minutes=request.context.available_minutes,
            intensity_band=_intensity_for(training_type),
            focus_codes=[_focus_for(training_type)],
        )
        for training_type in template.session_pattern
    ]
    return ValidatedTrainingPrescription(
        cycle_focus=(
            "specific"
            if request.context.race_type is not None
            and (request.context.days_until_race or 999) <= 56
            else "base"
        ),
        weekly_sessions=sessions,
        progression_mode=(
            "conservative"
            if request.context.experience_level == "beginner"
            or request.population_template_id
            in {
                "sedentary_beginner",
                "low_impact_fat_loss",
                "older_adult_foundation",
                "shift_worker_flexible",
                "return_to_training_guarded",
            }
            else "balanced"
        ),
    )


def _compile_safe_fallback(
    request: TrainingPrescriptionV2Request,
    provider_registry: ProviderRegistry | None = None,
) -> ValidatedTrainingPrescription:
    providers = provider_registry or ProviderRegistry.default()
    pattern = providers.resolve(
        request.context.primary_sport,
    ).safe_fallback_pattern
    sessions = [
        TrainingSessionBlueprint(
            training_type=pattern[index % len(pattern)],
            duration_minutes=request.context.available_minutes,
            intensity_band=_intensity_for(pattern[index % len(pattern)]),
            focus_codes=[_focus_for(pattern[index % len(pattern)])],
        )
        for index in range(min(request.context.weekly_training_days, 6))
    ]
    return ValidatedTrainingPrescription(
        cycle_focus="base",
        weekly_sessions=sessions,
        progression_mode=(
            "conservative"
            if request.context.experience_level == "beginner"
            else "balanced"
        ),
    )


def _intensity_for(training_type: TrainingTypeCode) -> IntensityBandCode:
    if training_type in {"easy_run", "long_run", "mobility"}:
        return "easy"
    return "moderate"


def _focus_for(training_type: TrainingTypeCode) -> FocusCode:
    mapping: dict[str, FocusCode] = {
        "easy_run": "aerobic_base",
        "tempo_run": "threshold",
        "interval_run": "speed",
        "long_run": "long_endurance",
        "strength": "full_body_strength",
        "hyrox": "hyrox_transition",
        "mobility": "mobility",
        "cross_training": "aerobic_base",
    }
    return mapping[training_type]


def _citations(
    retrieval: KnowledgeRetrievalResult,
) -> list[dict[str, str]]:
    principles = [
        {
            "id": item.id,
            "type": "principle",
            "title": item.title,
            "source_label": item.source_label,
            "source_section": item.source_section,
            "content_version": item.content_version,
        }
        for item in retrieval.principles
    ]
    templates = [
        {
            "id": item.id,
            "type": "training_template",
            "title": item.title,
            "source_label": item.source_label,
            "source_section": "结构模板",
            "content_version": item.content_version,
        }
        for item in retrieval.training_templates
    ]
    return [*principles, *templates]


def _v2_digest(
    request: TrainingPrescriptionV2Request,
    selection: SkillSelection,
    retrieval: KnowledgeRetrievalResult,
    provider_model: str,
    *,
    training_structure_enabled: bool = False,
) -> str:
    content = {
        "request": request.model_dump(mode="json", exclude={"force"}),
        "model": provider_model,
        "prompt_contract_version": TRAINING_PRESCRIPTION_PROMPT_CONTRACT,
        "skill_id": selection.manifest.id,
        "skill_version": selection.manifest.version,
        "skill_source_sha256": selection.source_sha256,
        "skill_runtime_sha256": selection.runtime_sha256,
        "skill_fragment_sha256": selection.fragment_sha256,
        "knowledge_version": retrieval.version,
        "structure_policy_version": (
            TRAINING_STRUCTURE_POLICY_VERSION
            if training_structure_enabled
            else "disabled"
        ),
        "principle_ids": [item.id for item in retrieval.principles],
        "training_template_ids": [item.id for item in retrieval.training_templates],
    }
    raw = json.dumps(content, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


def _backfill_training_structure(payload: dict[str, object]) -> None:
    """由服务端确定性回填结构标签，模型无须生成这些字段。"""
    cycle_focus = str(payload.get("cycle_focus", "base"))
    dimension_map: dict[str, tuple[list[str], list[str]]] = {
        "base": (
            ["stability", "breathing"],
            ["strength", "neural", "eccentric"],
        ),
        "build": (
            ["strength", "eccentric"],
            ["stability", "neural", "breathing"],
        ),
        "specific": (
            ["strength", "neural"],
            ["stability", "eccentric", "breathing"],
        ),
        "taper": (
            ["stability", "breathing"],
            ["strength", "neural", "eccentric"],
        ),
    }
    primary, touch = dimension_map.get(
        cycle_focus,
        dimension_map["base"],
    )
    raw_sessions = payload.get("weekly_sessions")
    if not isinstance(raw_sessions, list):
        return
    for raw_session in raw_sessions:
        if not isinstance(raw_session, dict):
            continue
        training_type = str(raw_session.get("training_type", ""))
        session_primary = list(primary)
        session_touch = list(touch)
        if training_type == "mobility":
            session_primary = ["stability", "breathing"]
            session_touch = []
        raw_session["structure_profile"] = {
            "primary_dimension_codes": session_primary,
            "touch_dimension_codes": session_touch,
            "leg_element_codes": _leg_elements_for(training_type),
        }


def _leg_elements_for(training_type: str) -> list[str]:
    if training_type in {"strength", "hyrox"}:
        return [
            "foot_ankle",
            "eccentric_landing",
            "dynamic_stability",
            "power",
        ]
    if training_type in {"interval_run", "tempo_run"}:
        return ["foot_ankle", "eccentric_landing", "dynamic_stability", "power"]
    if training_type in {"easy_run", "long_run"}:
        return ["foot_ankle", "eccentric_landing", "dynamic_stability"]
    return []


def _result_to_cache(
    result: TrainingPrescriptionModelResult,
) -> dict[str, object]:
    """跨用户缓存只保存严格枚举化处方，不保存请求正文。"""
    return {
        "prescription": result.prescription.model_dump(mode="json"),
        "input_tokens": result.input_tokens,
        "output_tokens": result.output_tokens,
        "prompt_cache_hit_tokens": result.prompt_cache_hit_tokens,
        "prompt_cache_miss_tokens": result.prompt_cache_miss_tokens,
    }


def _result_from_cache(
    payload: dict[str, object],
    *,
    cache_hit: bool,
) -> TrainingPrescriptionModelResult:
    prescription = ValidatedTrainingPrescription.model_validate(
        payload.get("prescription"),
    )
    if cache_hit:
        return TrainingPrescriptionModelResult(
            prescription=prescription,
            input_tokens=0,
            output_tokens=0,
            prompt_cache_hit_tokens=0,
            prompt_cache_miss_tokens=0,
        )
    return TrainingPrescriptionModelResult(
        prescription=prescription,
        input_tokens=_optional_int(payload.get("input_tokens")),
        output_tokens=_optional_int(payload.get("output_tokens")),
        prompt_cache_hit_tokens=_optional_int(
            payload.get("prompt_cache_hit_tokens"),
        ),
        prompt_cache_miss_tokens=_optional_int(
            payload.get("prompt_cache_miss_tokens"),
        ),
    )


def _optional_int(value: object) -> int | None:
    return value if isinstance(value, int) and not isinstance(value, bool) else None


def _elapsed_ms(started_at: float) -> int:
    return max(0, round((time.perf_counter() - started_at) * 1000))
