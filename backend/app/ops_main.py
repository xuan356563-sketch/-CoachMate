from fastapi import FastAPI

from app.api.ops import router as ops_router
from app.core.config import get_settings
from app.core.errors import ApiError, api_error_handler


def create_ops_app() -> FastAPI:
    """创建只应绑定私网或 127.0.0.1 的独立运营应用。"""
    settings = get_settings()
    app = FastAPI(
        title=f"{settings.app_name} Ops",
        version="0.1.0",
        description="仅提供聚合运维指标的私网应用。",
    )
    app.add_exception_handler(ApiError, api_error_handler)
    app.include_router(ops_router)
    return app


app = create_ops_app()
