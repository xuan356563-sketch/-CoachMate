from __future__ import annotations

from typing import Annotated, Any

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy.orm import Session

from app.api.auth import get_current_access_claims
from app.core.config import Settings, get_settings
from app.core.errors import ApiError
from app.core.security import AccessTokenClaims
from app.db.session import get_session
from app.services.sync_service import (
    IncomingMutation,
    SyncService,
    SyncWriteGate,
)

router = APIRouter(prefix="/v1/sync", tags=["云同步"])


class MutationBatchRequest(BaseModel):
    """一次最多接收功能开关允许数量的增量操作。"""

    model_config = ConfigDict(extra="forbid")

    mutations: list[IncomingMutation] = Field(min_length=1, max_length=100)


class MutationBatchResponse(BaseModel):
    """逐条返回应用、幂等重放或冲突结果。"""

    results: list[dict[str, Any]]


def get_sync_service(
    session: Annotated[Session, Depends(get_session)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> SyncService:
    """构造单请求同步服务。"""
    return SyncService(session, settings)


def get_sync_write_gate(
    settings: Annotated[Settings, Depends(get_settings)],
) -> SyncWriteGate:
    """构造生产 Redis 写入可用性门禁。"""
    return SyncWriteGate(settings)


@router.get("/snapshot", summary="获取当前账号云端快照")
def get_snapshot(
    claims: Annotated[AccessTokenClaims, Depends(get_current_access_claims)],
    service: Annotated[SyncService, Depends(get_sync_service)],
) -> dict[str, Any]:
    """新设备首次同步时读取全量非敏感投影。"""
    return service.snapshot(claims.user_id)


@router.post(
    "/mutations",
    response_model=MutationBatchResponse,
    summary="提交本地增量操作",
)
def post_mutations(
    request: MutationBatchRequest,
    claims: Annotated[AccessTokenClaims, Depends(get_current_access_claims)],
    service: Annotated[SyncService, Depends(get_sync_service)],
    gate: Annotated[SyncWriteGate, Depends(get_sync_write_gate)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> MutationBatchResponse:
    """只接收声明的同步实体和白名单字段。"""
    if len(request.mutations) > settings.sync_batch_limit:
        raise ApiError(
            422,
            "sync_batch_too_large",
            f"单次同步最多提交 {settings.sync_batch_limit} 条操作。",
        )
    service.ensure_enabled()
    gate.check()
    return MutationBatchResponse(
        results=service.apply_mutations(claims.user_id, request.mutations),
    )


@router.get("/changes", summary="按游标获取云端增量")
def get_changes(
    claims: Annotated[AccessTokenClaims, Depends(get_current_access_claims)],
    service: Annotated[SyncService, Depends(get_sync_service)],
    after: Annotated[int, Query(ge=0)] = 0,
    limit: Annotated[int, Query(ge=1, le=100)] = 100,
) -> dict[str, Any]:
    """只返回当前账号在指定游标后的变化。"""
    return service.changes(claims.user_id, after=after, limit=limit)
