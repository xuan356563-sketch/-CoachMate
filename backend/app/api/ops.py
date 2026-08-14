from __future__ import annotations

from typing import Annotated, Any

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.core.config import Settings, get_settings
from app.core.errors import ApiError
from app.db.session import get_session
from app.services.ops_metrics import OpsMetricsService

router = APIRouter(prefix="/ops/v1", tags=["私网运营"])


def ensure_ops_enabled(
    settings: Annotated[Settings, Depends(get_settings)],
) -> None:
    """未显式启用时隐藏全部运营接口。"""
    if not settings.ops_enabled:
        raise ApiError(404, "ops_not_found", "接口不存在")


def get_ops_metrics_service(
    session: Annotated[Session, Depends(get_session)],
) -> OpsMetricsService:
    return OpsMetricsService(session)


@router.get("/summary", dependencies=[Depends(ensure_ops_enabled)])
def get_summary(
    service: Annotated[OpsMetricsService, Depends(get_ops_metrics_service)],
) -> dict[str, int]:
    return service.summary()


@router.get("/sync-health", dependencies=[Depends(ensure_ops_enabled)])
def get_sync_health(
    service: Annotated[OpsMetricsService, Depends(get_ops_metrics_service)],
) -> dict[str, Any]:
    return service.sync_health()


@router.get("/ai-usage", dependencies=[Depends(ensure_ops_enabled)])
def get_ai_usage(
    service: Annotated[OpsMetricsService, Depends(get_ops_metrics_service)],
) -> dict[str, Any]:
    return service.ai_usage()


@router.get("/deletion-jobs", dependencies=[Depends(ensure_ops_enabled)])
def get_deletion_jobs(
    service: Annotated[OpsMetricsService, Depends(get_ops_metrics_service)],
) -> dict[str, Any]:
    return service.deletion_jobs()
