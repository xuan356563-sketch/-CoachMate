from __future__ import annotations

import time
from functools import lru_cache
from typing import Annotated, Any, Literal
from uuid import UUID

from fastapi import APIRouter, Depends, File, Form, Request, Response, status
from pydantic import BaseModel, ConfigDict
from sqlalchemy.orm import Session

from app.api.auth import get_current_access_claims
from app.core.config import Settings, get_settings
from app.core.errors import ApiError
from app.core.security import AccessTokenClaims
from app.db.session import get_session
from app.models.ai import AiArtifact
from app.services.ai_chat import (
    AI_CHAT_PROMPT_CONTRACT,
    AiChatRequest,
    AiChatResponse,
    AiChatService,
    HttpDeepSeekChatClient,
)
from app.services.ai_generation import (
    AiArtifactService,
    AiTextGenerationRequest,
    HttpDeepSeekClient,
    HttpMiniMaxMotionClient,
)
from app.services.ai_generation_rate_limit import AiGenerationRateLimiter
from app.services.ai_response_cache import AiResponseCache
from app.services.ai_usage import AiUsageRecorder
from app.services.knowledge_catalog import KnowledgeCatalogService
from app.services.plan_revision import (
    HttpDeepSeekPlanRevisionClient,
    PlanRevisionRequest,
    PlanRevisionService,
)
from app.services.profile_proposal import (
    HttpDeepSeekProfileProposalClient,
    ProfileProposalRequest,
    ProfileProposalService,
)
from app.services.subscription_billing import SubscriptionBillingService
from app.services.training_prescription import (
    HttpDeepSeekPrescriptionClient,
    TrainingPrescriptionRequest,
    TrainingPrescriptionService,
)
from app.services.training_prescription_v2 import (
    TrainingPrescriptionV2Request,
    TrainingPrescriptionV2Service,
)
from app.services.training_skills import TrainingSkillRegistry

router = APIRouter(prefix="/v1/ai", tags=["AI 产物"])
v2_router = APIRouter(prefix="/v2/ai", tags=["AI 产物 V2"])


class AiArtifactResponse(BaseModel):
    """Flutter 可渲染的稳定 AI 产物结构。"""

    model_config = ConfigDict(from_attributes=True)

    id: UUID
    capability: str
    artifact_type: str
    schema_version: int
    decision_status: Literal["pending", "accepted", "rejected"]
    context_digest: str
    payload: dict[str, Any]
    warnings: list[str]
    provider: str
    model: str
    generated_at: str
    decided_at: str | None

    @classmethod
    def from_artifact(
        cls,
        artifact: AiArtifact,
        *,
        cache_hit: bool | None = None,
    ) -> "AiArtifactResponse":
        payload = dict(artifact.payload)
        if cache_hit is not None and isinstance(payload.get("generation_meta"), dict):
            payload["generation_meta"] = {
                **payload["generation_meta"],
                "cache_hit": cache_hit,
                "app_cache_hit": cache_hit,
            }
        return cls(
            id=artifact.id,
            capability=artifact.capability,
            artifact_type=artifact.artifact_type,
            schema_version=artifact.schema_version,
            decision_status=artifact.decision_status,
            context_digest=artifact.context_digest,
            payload=payload,
            warnings=artifact.warnings,
            provider=artifact.provider,
            model=artifact.model,
            generated_at=artifact.generated_at.isoformat(),
            decided_at=artifact.decided_at.isoformat() if artifact.decided_at else None,
        )


class AiArtifactListResponse(BaseModel):
    artifacts: list[AiArtifactResponse]


class AiArtifactDecisionRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    decision: Literal["accepted", "rejected"]


class TrainingSkillCapabilityResponse(BaseModel):
    id: str
    version: str
    display_name: str
    sports: list[str]
    source_sha256: str
    runtime_sha256: str
    fragment_sha256: dict[str, str]


class TrainingPrescriptionCapabilitiesResponse(BaseModel):
    enabled: bool
    contract_version: int
    skills: list[TrainingSkillCapabilityResponse]
    disabled_reason: str | None = None


def get_ai_artifact_service(
    session: Annotated[Session, Depends(get_session)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> AiArtifactService:
    """为一次请求构造不共享原始输入的 AI 编排服务。"""
    return AiArtifactService(
        session,
        settings,
        HttpDeepSeekClient(settings),
        HttpMiniMaxMotionClient(settings),
    )


def get_ai_usage_recorder(
    session: Annotated[Session, Depends(get_session)],
) -> AiUsageRecorder:
    return AiUsageRecorder(session)


def get_subscription_billing_service(
    session: Annotated[Session, Depends(get_session)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> SubscriptionBillingService:
    """集中裁决所有新计划生成和重排入口的会员权益。"""
    return SubscriptionBillingService(session, settings)


@lru_cache
def get_training_skill_registry() -> TrainingSkillRegistry:
    """进程内复用已通过完整性校验的内置 Skill。"""
    return TrainingSkillRegistry.default()


def get_training_prescription_service(
    session: Annotated[Session, Depends(get_session)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> TrainingPrescriptionService:
    """构造 Skill 选择、DeepSeek 调用和产物持久化服务。"""
    return TrainingPrescriptionService(
        session,
        settings,
        get_training_skill_registry(),
        HttpDeepSeekPrescriptionClient(settings),
    )


def get_training_prescription_v2_service(
    session: Annotated[Session, Depends(get_session)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> TrainingPrescriptionV2Service:
    """构造带结构化知识检索和本地模板编译的 V2 服务。"""
    return TrainingPrescriptionV2Service(
        session=session,
        settings=settings,
        registry=get_training_skill_registry(),
        client=HttpDeepSeekPrescriptionClient(settings),
        knowledge=KnowledgeCatalogService(session),
        response_cache=get_ai_response_cache(),
    )


def get_profile_proposal_service(
    session: Annotated[Session, Depends(get_session)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> ProfileProposalService:
    """构造只处理已脱敏训练偏好的画像提议服务。"""
    return ProfileProposalService(
        session=session,
        settings=settings,
        client=HttpDeepSeekProfileProposalClient(settings),
        response_cache=get_ai_response_cache(),
    )


def get_plan_revision_service(
    session: Annotated[Session, Depends(get_session)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> PlanRevisionService:
    """构造只生成待确认差异的剩余周期重排服务。"""
    return PlanRevisionService(
        session=session,
        settings=settings,
        client=HttpDeepSeekPlanRevisionClient(settings),
        response_cache=get_ai_response_cache(),
    )


@lru_cache
def get_ai_response_cache() -> AiResponseCache:
    """复用不保存原始输入的 Redis 响应缓存和 single-flight。"""
    return AiResponseCache(get_settings().redis_url)


@lru_cache
def _cached_ai_rate_limiter() -> AiGenerationRateLimiter:
    return AiGenerationRateLimiter(get_settings())


def get_ai_rate_limiter() -> AiGenerationRateLimiter:
    return _cached_ai_rate_limiter()


@lru_cache
def get_ai_chat_service() -> AiChatService:
    """复用仅保存短时响应的无状态聊天服务。"""
    settings = get_settings()
    return AiChatService(
        HttpDeepSeekChatClient(settings),
        response_cache=get_ai_response_cache(),
        model=settings.deepseek_model,
    )


@router.get(
    "/training-prescriptions/capabilities",
    response_model=TrainingPrescriptionCapabilitiesResponse,
    summary="读取已审核训练 Skill 能力",
)
def get_training_prescription_capabilities(
    _claims: Annotated[AccessTokenClaims, Depends(get_current_access_claims)],
    service: Annotated[
        TrainingPrescriptionService,
        Depends(get_training_prescription_service),
    ],
) -> TrainingPrescriptionCapabilitiesResponse:
    """只暴露版本、覆盖标签和哈希，不返回 Skill 正文。"""
    return TrainingPrescriptionCapabilitiesResponse.model_validate(
        service.capabilities(),
    )


@router.post(
    "/chat",
    summary="拒绝已停用的自由文本训练对话协议",
)
async def retired_chat(
    _claims: Annotated[AccessTokenClaims, Depends(get_current_access_claims)],
) -> None:
    """旧协议可能携带健康正文，统一失败关闭且不解析请求体。"""
    raise ApiError(
        410,
        "ai_chat_contract_retired",
        "当前版本不再接收自由文本云端对话，请升级应用后使用固定训练问题。",
    )


@v2_router.post(
    "/chat",
    response_model=AiChatResponse,
    summary="进行结构化无状态训练对话",
)
async def structured_chat(
    request: AiChatRequest,
    claims: Annotated[AccessTokenClaims, Depends(get_current_access_claims)],
    limiter: Annotated[AiGenerationRateLimiter, Depends(get_ai_rate_limiter)],
    service: Annotated[AiChatService, Depends(get_ai_chat_service)],
    recorder: Annotated[AiUsageRecorder, Depends(get_ai_usage_recorder)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> AiChatResponse:
    """只接收枚举和数值训练约束；协议不包含自由文本。"""
    limiter.check(claims.user_id)
    started_at = time.perf_counter()
    try:
        response = await service.reply(claims.user_id, request)
    except ApiError as error:
        recorder.record(
            provider="deepseek",
            model=settings.deepseek_model,
            capability="chat",
            prompt_contract_version=AI_CHAT_PROMPT_CONTRACT,
            input_tokens=None,
            output_tokens=None,
            latency_ms=_elapsed_ms(started_at),
            result_code=error.code,
            request_id=request.request_id,
        )
        raise
    recorder.record(
        provider=response.provider,
        model=response.model,
        capability="chat",
        prompt_contract_version=AI_CHAT_PROMPT_CONTRACT,
        input_tokens=response.input_tokens,
        output_tokens=response.output_tokens,
        prompt_cache_hit_tokens=response.prompt_cache_hit_tokens,
        prompt_cache_miss_tokens=response.prompt_cache_miss_tokens,
        latency_ms=_elapsed_ms(started_at),
        result_code="cached" if response.app_cache_hit else "generated",
        request_id=request.request_id,
    )
    return response


@router.post(
    "/training-prescriptions",
    response_model=AiArtifactResponse,
    status_code=status.HTTP_201_CREATED,
    summary="使用内置 Skill 生成严格训练处方",
)
async def generate_training_prescription(
    http_request: Request,
    request: TrainingPrescriptionRequest,
    claims: Annotated[AccessTokenClaims, Depends(get_current_access_claims)],
    limiter: Annotated[AiGenerationRateLimiter, Depends(get_ai_rate_limiter)],
    service: Annotated[
        TrainingPrescriptionService,
        Depends(get_training_prescription_service),
    ],
    entitlement: Annotated[
        SubscriptionBillingService,
        Depends(get_subscription_billing_service),
    ],
) -> AiArtifactResponse:
    """处方保持 pending，确认后仍由 Flutter 本地编译器最终裁决。"""
    entitlement.ensure_can_generate(claims.user_id)
    limiter.check(claims.user_id)
    artifact, cache_hit = await service.generate(
        claims.user_id,
        request,
        request_id=http_request.headers.get("X-Request-Id"),
    )
    return AiArtifactResponse.from_artifact(artifact, cache_hit=cache_hit)


@router.post(
    "/profile-proposals",
    response_model=AiArtifactResponse,
    status_code=status.HTTP_201_CREATED,
    summary="根据已脱敏训练偏好生成画像提议",
)
async def generate_profile_proposal(
    request: ProfileProposalRequest,
    claims: Annotated[AccessTokenClaims, Depends(get_current_access_claims)],
    limiter: Annotated[AiGenerationRateLimiter, Depends(get_ai_rate_limiter)],
    service: Annotated[
        ProfileProposalService,
        Depends(get_profile_proposal_service),
    ],
) -> AiArtifactResponse:
    """只生成 pending 提议，不写入正式用户档案。"""
    limiter.check(claims.user_id)
    artifact, cache_hit = await service.propose(claims.user_id, request)
    return AiArtifactResponse.from_artifact(artifact, cache_hit=cache_hit)


@router.post(
    "/plan-revisions",
    response_model=AiArtifactResponse,
    status_code=status.HTTP_201_CREATED,
    summary="生成剩余周期重排提议",
)
async def generate_plan_revision(
    http_request: Request,
    request: PlanRevisionRequest,
    claims: Annotated[AccessTokenClaims, Depends(get_current_access_claims)],
    limiter: Annotated[AiGenerationRateLimiter, Depends(get_ai_rate_limiter)],
    service: Annotated[
        PlanRevisionService,
        Depends(get_plan_revision_service),
    ],
    entitlement: Annotated[
        SubscriptionBillingService,
        Depends(get_subscription_billing_service),
    ],
) -> AiArtifactResponse:
    """只保存 pending 差异，确认前不覆盖当前计划。"""
    entitlement.ensure_can_generate(claims.user_id)
    limiter.check(claims.user_id)
    artifact, cache_hit = await service.generate(
        claims.user_id,
        request,
        request_id=http_request.headers.get("X-Request-Id"),
    )
    return AiArtifactResponse.from_artifact(artifact, cache_hit=cache_hit)


@v2_router.post(
    "/training-prescriptions",
    response_model=AiArtifactResponse,
    status_code=status.HTTP_201_CREATED,
    summary="使用已审核知识目录生成 V2 训练处方",
)
async def generate_training_prescription_v2(
    http_request: Request,
    request: TrainingPrescriptionV2Request,
    claims: Annotated[AccessTokenClaims, Depends(get_current_access_claims)],
    limiter: Annotated[AiGenerationRateLimiter, Depends(get_ai_rate_limiter)],
    service: Annotated[
        TrainingPrescriptionV2Service,
        Depends(get_training_prescription_v2_service),
    ],
    entitlement: Annotated[
        SubscriptionBillingService,
        Depends(get_subscription_billing_service),
    ],
) -> AiArtifactResponse:
    """本地模板或云端适配都只生成待确认产物。"""
    entitlement.ensure_can_generate(claims.user_id)
    limiter.check(claims.user_id)
    artifact, cache_hit = await service.generate(
        claims.user_id,
        request,
        request_id=http_request.headers.get("X-Request-Id"),
    )
    return AiArtifactResponse.from_artifact(artifact, cache_hit=cache_hit)


@router.post(
    "/generations",
    response_model=AiArtifactResponse,
    status_code=status.HTTP_201_CREATED,
    summary="生成训练计划或恢复建议",
)
async def generate_text_artifact(
    http_request: Request,
    request: AiTextGenerationRequest,
    claims: Annotated[AccessTokenClaims, Depends(get_current_access_claims)],
    limiter: Annotated[AiGenerationRateLimiter, Depends(get_ai_rate_limiter)],
    service: Annotated[AiArtifactService, Depends(get_ai_artifact_service)],
    entitlement: Annotated[
        SubscriptionBillingService,
        Depends(get_subscription_billing_service),
    ],
) -> AiArtifactResponse:
    """仅接收去标识化训练摘要，持久化通过 Schema 校验的 AI 结果。"""
    entitlement.ensure_can_generate(claims.user_id)
    limiter.check(claims.user_id)
    artifact = await service.generate_text(
        claims.user_id,
        request,
        request_id=http_request.headers.get("X-Request-Id"),
    )
    return AiArtifactResponse.from_artifact(artifact)


@router.post(
    "/motion-analysis",
    response_model=AiArtifactResponse,
    status_code=status.HTTP_201_CREATED,
    summary="确认后分析动作图片",
)
async def generate_motion_artifact(
    http_request: Request,
    image: Annotated[bytes, File(description="确认上传的动作照片")],
    rule_id: Annotated[str, Form(max_length=64)],
    claims: Annotated[AccessTokenClaims, Depends(get_current_access_claims)],
    limiter: Annotated[AiGenerationRateLimiter, Depends(get_ai_rate_limiter)],
    service: Annotated[AiArtifactService, Depends(get_ai_artifact_service)],
    local_pose_summary: Annotated[str, Form(max_length=500)] = "",
) -> AiArtifactResponse:
    """图片只在内存中去元数据并发送给供应商，不写入日志、磁盘或数据库。"""
    limiter.check(claims.user_id)
    artifact = await service.generate_motion(
        claims.user_id,
        image=image,
        rule_id=rule_id,
        local_pose_summary=local_pose_summary,
        request_id=http_request.headers.get("X-Request-Id"),
    )
    return AiArtifactResponse.from_artifact(artifact)


@router.get("/artifacts", response_model=AiArtifactListResponse, summary="读取 AI 产物")
def list_artifacts(
    claims: Annotated[AccessTokenClaims, Depends(get_current_access_claims)],
    service: Annotated[AiArtifactService, Depends(get_ai_artifact_service)],
    capability: str | None = None,
) -> AiArtifactListResponse:
    """只返回当前用户的结果，供跨设备本地缓存恢复。"""
    return AiArtifactListResponse(
        artifacts=[
            AiArtifactResponse.from_artifact(item)
            for item in service.list_artifacts(claims.user_id, capability)
        ],
    )


@router.post(
    "/artifacts/{artifact_id}/decision",
    response_model=AiArtifactResponse,
    summary="确认或拒绝 AI 结果",
)
def decide_artifact(
    artifact_id: UUID,
    request: AiArtifactDecisionRequest,
    claims: Annotated[AccessTokenClaims, Depends(get_current_access_claims)],
    service: Annotated[AiArtifactService, Depends(get_ai_artifact_service)],
) -> AiArtifactResponse:
    """记录用户决定，应用逻辑仍由 Flutter 本地规则最终裁决。"""
    artifact = service.decide(claims.user_id, artifact_id, request.decision)
    return AiArtifactResponse.from_artifact(artifact)


@router.delete(
    "/artifacts/{artifact_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="删除 AI 产物",
)
def delete_artifact(
    artifact_id: UUID,
    claims: Annotated[AccessTokenClaims, Depends(get_current_access_claims)],
    service: Annotated[AiArtifactService, Depends(get_ai_artifact_service)],
) -> Response:
    """删除云端产物，不影响本地训练日志和计划。"""
    service.delete(claims.user_id, artifact_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


def _elapsed_ms(started_at: float) -> int:
    return round((time.perf_counter() - started_at) * 1000)
