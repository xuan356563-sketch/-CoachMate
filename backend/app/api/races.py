from __future__ import annotations

import time
from functools import lru_cache
from typing import Annotated

from fastapi import APIRouter, Depends, File, Request
from sqlalchemy.orm import Session

from app.api.auth import get_current_access_claims
from app.core.config import Settings, get_settings
from app.core.errors import ApiError
from app.core.security import AccessTokenClaims
from app.db.session import get_session
from app.services.ai_usage import AiUsageRecorder
from app.services.race_recognition import (
    HttpMiniMaxClient,
    RaceRecognitionResult,
    RaceRecognitionService,
)
from app.services.race_recognition_rate_limit import RaceRecognitionRateLimiter

router = APIRouter(prefix="/v1/races", tags=["赛事"])


def get_race_recognition_service(
    settings: Annotated[Settings, Depends(get_settings)],
) -> RaceRecognitionService:
    return RaceRecognitionService(settings, HttpMiniMaxClient(settings))


@lru_cache
def _cached_rate_limiter() -> RaceRecognitionRateLimiter:
    return RaceRecognitionRateLimiter(get_settings())


def get_race_recognition_rate_limiter() -> RaceRecognitionRateLimiter:
    return _cached_rate_limiter()


def get_race_ai_usage_recorder(
    session: Annotated[Session, Depends(get_session)],
) -> AiUsageRecorder:
    return AiUsageRecorder(session)


@router.post(
    "/image-recognition",
    response_model=RaceRecognitionResult,
    summary="识别赛事图片",
)
async def recognize_race_image(
    request: Request,
    image: Annotated[bytes, File(description="JPEG、PNG、GIF 或 WebP 赛事图片")],
    claims: Annotated[AccessTokenClaims, Depends(get_current_access_claims)],
    rate_limiter: Annotated[
        RaceRecognitionRateLimiter,
        Depends(get_race_recognition_rate_limiter),
    ],
    service: Annotated[
        RaceRecognitionService,
        Depends(get_race_recognition_service),
    ],
    recorder: Annotated[
        AiUsageRecorder,
        Depends(get_race_ai_usage_recorder),
    ],
    settings: Annotated[Settings, Depends(get_settings)],
) -> RaceRecognitionResult:
    """识别结果仅返回客户端，不写入文件、日志或数据库。"""
    rate_limiter.check(claims.user_id)
    started_at = time.perf_counter()
    request_id = request.headers.get("X-Request-Id")
    try:
        result = await service.recognize(image)
    except ApiError as error:
        recorder.record(
            provider="minimax",
            model=settings.minimax_model,
            input_tokens=None,
            output_tokens=None,
            latency_ms=_elapsed_ms(started_at),
            result_code=error.code,
            request_id=request_id,
        )
        raise
    recorder.record(
        provider=result.provider,
        model=result.model,
        input_tokens=None,
        output_tokens=None,
        latency_ms=_elapsed_ms(started_at),
        result_code="generated",
        request_id=request_id,
    )
    return result


def _elapsed_ms(started_at: float) -> int:
    return round((time.perf_counter() - started_at) * 1000)
