from __future__ import annotations

from datetime import datetime
from typing import Annotated, Literal
from uuid import UUID

from fastapi import APIRouter, Depends, status
from fastapi.encoders import jsonable_encoder
from fastapi.responses import JSONResponse
from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator
from sqlalchemy.orm import Session

from app.api.auth import (
    get_auth_redis_gate,
    get_current_access_claims,
    get_email_provider,
)
from app.core.config import Settings, get_settings
from app.core.security import AccessTokenClaims
from app.db.session import get_session
from app.services.account_lifecycle import AccountLifecycleService
from app.services.auth_redis_gate import AuthRedisGate
from app.services.email_provider import EmailProvider

router = APIRouter(prefix="/v1/account", tags=["账号生命周期"])


class DeletionChallengeRequest(BaseModel):
    """使用当前账号邮箱申请删除复核验证码。"""

    model_config = ConfigDict(extra="forbid")

    email: EmailStr


class DeletionChallengeResponse(BaseModel):
    """响应不包含邮箱或验证码。"""

    challenge_id: UUID
    expires_in_seconds: int


class DeletionRequestInput(BaseModel):
    """提交邮箱复核验证码并进入删除撤销期。"""

    model_config = ConfigDict(extra="forbid")

    email: EmailStr
    challenge_id: UUID
    code: str = Field(min_length=6, max_length=6)

    @field_validator("code")
    @classmethod
    def validate_code(cls, value: str) -> str:
        if not value.isdigit():
            raise ValueError("验证码必须是六位数字")
        return value


class DeletionStatusResponse(BaseModel):
    """不返回身份标识的删除任务状态。"""

    status: Literal["not_requested", "pending", "cancelled"]
    request_id: UUID | None = None
    requested_at: datetime | None = None
    purge_after: datetime | None = None
    grace_period_days: int


class HealthProfileCloudConsentRequest(BaseModel):
    """健康资料云同步授权与撤回请求。"""

    model_config = ConfigDict(extra="forbid")

    granted: bool
    document_version: str = Field(min_length=1, max_length=64)


class HealthProfileCloudConsentResponse(BaseModel):
    """只返回授权状态和版本，不返回任何健康资料。"""

    granted: bool
    document_version: str
    changed_at: datetime


class CoachCloudProjectionConsentRequest(BaseModel):
    """Coach 最小结构化云投影的独立授权与撤回。"""

    model_config = ConfigDict(extra="forbid")

    granted: bool
    document_version: str = Field(min_length=1, max_length=64)


class CoachCloudProjectionConsentResponse(BaseModel):
    granted: bool
    document_version: str
    changed_at: datetime


def get_account_lifecycle_service(
    session: Annotated[Session, Depends(get_session)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> AccountLifecycleService:
    """构造单请求账号生命周期服务。"""
    return AccountLifecycleService(session, settings)


@router.get("/export", summary="导出当前账号云端数据")
def export_account(
    claims: Annotated[AccessTokenClaims, Depends(get_current_access_claims)],
    service: Annotated[
        AccountLifecycleService,
        Depends(get_account_lifecycle_service),
    ],
) -> JSONResponse:
    """即时生成 JSON，不在数据库复制导出正文。"""
    payload = service.export(claims.user_id)
    export_id = payload["export_id"]
    return JSONResponse(
        content=jsonable_encoder(payload),
        headers={
            "Content-Disposition": (
                f'attachment; filename="trainmate-export-{export_id}.json"'
            ),
            "Cache-Control": "no-store",
        },
    )


@router.put(
    "/consents/health-profile-cloud",
    response_model=HealthProfileCloudConsentResponse,
    summary="授予或撤回健康资料云同步授权",
)
def set_health_profile_cloud_consent(
    request: HealthProfileCloudConsentRequest,
    claims: Annotated[AccessTokenClaims, Depends(get_current_access_claims)],
    service: Annotated[
        AccountLifecycleService,
        Depends(get_account_lifecycle_service),
    ],
) -> HealthProfileCloudConsentResponse:
    consent = service.set_health_profile_cloud_consent(
        claims.user_id,
        granted=request.granted,
        document_version=request.document_version,
    )
    changed_at = consent.granted_at if request.granted else consent.revoked_at
    assert changed_at is not None
    return HealthProfileCloudConsentResponse(
        granted=request.granted,
        document_version=consent.document_version,
        changed_at=changed_at,
    )


@router.put(
    "/consents/coach-cloud-projection",
    response_model=CoachCloudProjectionConsentResponse,
    summary="授予或撤回 Coach 最小云投影授权",
)
def set_coach_cloud_projection_consent(
    request: CoachCloudProjectionConsentRequest,
    claims: Annotated[AccessTokenClaims, Depends(get_current_access_claims)],
    service: Annotated[
        AccountLifecycleService,
        Depends(get_account_lifecycle_service),
    ],
) -> CoachCloudProjectionConsentResponse:
    consent = service.set_coach_cloud_projection_consent(
        claims.user_id,
        granted=request.granted,
        document_version=request.document_version,
    )
    changed_at = consent.granted_at if request.granted else consent.revoked_at
    assert changed_at is not None
    return CoachCloudProjectionConsentResponse(
        granted=request.granted,
        document_version=consent.document_version,
        changed_at=changed_at,
    )


@router.post(
    "/deletion-challenges",
    response_model=DeletionChallengeResponse,
    status_code=status.HTTP_201_CREATED,
    summary="申请账号删除复核验证码",
)
def request_deletion_challenge(
    request: DeletionChallengeRequest,
    claims: Annotated[AccessTokenClaims, Depends(get_current_access_claims)],
    service: Annotated[
        AccountLifecycleService,
        Depends(get_account_lifecycle_service),
    ],
    email_provider: Annotated[EmailProvider, Depends(get_email_provider)],
    settings: Annotated[Settings, Depends(get_settings)],
    gate: Annotated[AuthRedisGate, Depends(get_auth_redis_gate)],
) -> DeletionChallengeResponse:
    gate.check()
    challenge_id = service.request_deletion_challenge(
        claims.user_id,
        str(request.email),
        email_provider,
    )
    return DeletionChallengeResponse(
        challenge_id=challenge_id,
        expires_in_seconds=settings.email_code_ttl_seconds,
    )


@router.post(
    "/deletion-requests",
    response_model=DeletionStatusResponse,
    status_code=status.HTTP_201_CREATED,
    summary="申请删除账号",
)
def request_deletion(
    request: DeletionRequestInput,
    claims: Annotated[AccessTokenClaims, Depends(get_current_access_claims)],
    service: Annotated[
        AccountLifecycleService,
        Depends(get_account_lifecycle_service),
    ],
    settings: Annotated[Settings, Depends(get_settings)],
    gate: Annotated[AuthRedisGate, Depends(get_auth_redis_gate)],
) -> DeletionStatusResponse:
    gate.check()
    deletion_request = service.request_deletion(
        claims.user_id,
        email_value=str(request.email),
        challenge_id=request.challenge_id,
        code=request.code,
    )
    return _status_response(deletion_request, settings)


@router.post(
    "/deletion-cancellations",
    response_model=DeletionStatusResponse,
    summary="在撤销期内取消账号删除",
)
def cancel_deletion(
    claims: Annotated[AccessTokenClaims, Depends(get_current_access_claims)],
    service: Annotated[
        AccountLifecycleService,
        Depends(get_account_lifecycle_service),
    ],
    settings: Annotated[Settings, Depends(get_settings)],
) -> DeletionStatusResponse:
    return _status_response(
        service.cancel_deletion(claims.user_id),
        settings,
    )


@router.get(
    "/deletion-status",
    response_model=DeletionStatusResponse,
    summary="读取账号删除状态",
)
def deletion_status(
    claims: Annotated[AccessTokenClaims, Depends(get_current_access_claims)],
    service: Annotated[
        AccountLifecycleService,
        Depends(get_account_lifecycle_service),
    ],
    settings: Annotated[Settings, Depends(get_settings)],
) -> DeletionStatusResponse:
    deletion_request = service.deletion_status(claims.user_id)
    if deletion_request is None:
        return DeletionStatusResponse(
            status="not_requested",
            grace_period_days=settings.account_deletion_grace_days,
        )
    return _status_response(deletion_request, settings)


def _status_response(
    deletion_request,
    settings: Settings,
) -> DeletionStatusResponse:
    return DeletionStatusResponse(
        status=deletion_request.status,
        request_id=deletion_request.id,
        requested_at=deletion_request.requested_at,
        purge_after=deletion_request.purge_after,
        grace_period_days=settings.account_deletion_grace_days,
    )
