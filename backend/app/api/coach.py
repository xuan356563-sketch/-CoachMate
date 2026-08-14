from __future__ import annotations

from datetime import datetime
from typing import Annotated

from fastapi import APIRouter, Depends, Response, status
from pydantic import BaseModel, ConfigDict
from sqlalchemy.orm import Session

from app.api.auth import get_current_access_claims
from app.core.config import Settings, get_settings
from app.core.security import AccessTokenClaims
from app.db.session import get_session
from app.services.coach.contracts import (
    CoachEvaluationRequest,
    CoachEvaluationResponse,
    CoachProjectionPutRequest,
)
from app.services.coach.projection_service import CoachProjectionService

router = APIRouter(prefix="/v1/coach", tags=["Coach"])


class CoachProjectionResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    version: int
    snapshot_id: str
    snapshot_digest: str
    memory_set_digest: str
    expires_at: datetime


def get_coach_projection_service(
    session: Annotated[Session, Depends(get_session)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> CoachProjectionService:
    return CoachProjectionService(session, settings)


@router.put(
    "/projections/current",
    response_model=CoachProjectionResponse,
    summary="整体替换当前 Coach 最小云投影",
)
def replace_current_projection(
    request: CoachProjectionPutRequest,
    claims: Annotated[AccessTokenClaims, Depends(get_current_access_claims)],
    service: Annotated[
        CoachProjectionService, Depends(get_coach_projection_service)
    ],
) -> CoachProjectionResponse:
    return CoachProjectionResponse.model_validate(
        service.replace_current(claims.user_id, request)
    )


@router.delete(
    "/projections/current",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="删除当前账号全部 Coach 云投影",
)
def delete_current_projection(
    claims: Annotated[AccessTokenClaims, Depends(get_current_access_claims)],
    service: Annotated[
        CoachProjectionService, Depends(get_coach_projection_service)
    ],
) -> Response:
    service.delete_current(claims.user_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post(
    "/evaluations",
    response_model=CoachEvaluationResponse,
    summary="基于服务端已保存投影执行确定性 Coach 评估",
)
def evaluate_coach(
    request: CoachEvaluationRequest,
    claims: Annotated[AccessTokenClaims, Depends(get_current_access_claims)],
    service: Annotated[
        CoachProjectionService, Depends(get_coach_projection_service)
    ],
) -> CoachEvaluationResponse:
    return service.evaluate(claims.user_id, request)
