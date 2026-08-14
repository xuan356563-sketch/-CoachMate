from fastapi import FastAPI
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware

from app.api.account import router as account_router
from app.api.ai import router as ai_router
from app.api.ai import v2_router as ai_v2_router
from app.api.auth import router as auth_router
from app.api.billing import router as billing_router
from app.api.coach import router as coach_router
from app.api.health import router as health_router
from app.api.knowledge import router as knowledge_router
from app.api.races import router as races_router
from app.api.sync import router as sync_router
from app.core.config import get_settings
from app.core.errors import (
    ApiError,
    api_error_handler,
    request_validation_error_handler,
)


def create_app() -> FastAPI:
    """创建 API 应用，保持业务路由按模块注册。"""
    settings = get_settings()
    app = FastAPI(
        title=settings.app_name,
        version="0.1.0",
        description="TrainFlow 大陆云端后端账号与会话基础。",
    )
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origin_list,
        allow_credentials=False,
        allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE"],
        allow_headers=["Authorization", "Content-Type", "X-Request-Id"],
    )
    app.add_exception_handler(ApiError, api_error_handler)
    app.add_exception_handler(
        RequestValidationError,
        request_validation_error_handler,
    )
    app.include_router(health_router)
    app.include_router(auth_router)
    app.include_router(account_router)
    app.include_router(billing_router)
    app.include_router(coach_router)
    app.include_router(races_router)
    app.include_router(ai_router)
    app.include_router(ai_v2_router)
    app.include_router(knowledge_router)
    app.include_router(sync_router)
    return app


app = create_app()
