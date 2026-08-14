from functools import lru_cache
from pathlib import Path
from typing import Annotated, Literal, Protocol

import redis
from alembic.config import Config
from alembic.script import ScriptDirectory
from fastapi import APIRouter, Depends, Response, status
from pydantic import BaseModel
from sqlalchemy import text

from app.core.config import Settings, get_settings
from app.db.session import get_engine

router = APIRouter(tags=["运行状态"])


class HealthResponse(BaseModel):
    """服务存活检查响应。"""

    status: Literal["ok"]
    service: str
    environment: str


class ReadinessChecks(BaseModel):
    """生产依赖的最小就绪状态。"""

    database: Literal["ok", "error"]
    redis: Literal["ok", "error"]
    migration: Literal["ok", "error"]


class ReadinessResponse(BaseModel):
    """不暴露连接信息和异常正文的就绪检查响应。"""

    status: Literal["ready", "not_ready"]
    service: str
    environment: str
    version: str
    checks: ReadinessChecks


class ReadinessProbe(Protocol):
    """允许测试替换基础设施探针，避免连接真实服务。"""

    def check(self) -> ReadinessChecks:
        """检查数据库、Redis 和迁移版本。"""


@lru_cache
def _expected_migration_head() -> str:
    """读取随应用镜像发布的唯一 Alembic Head。"""
    backend_root = Path(__file__).resolve().parents[2]
    config = Config(str(backend_root / "alembic.ini"))
    config.set_main_option("script_location", str(backend_root / "alembic"))
    heads = ScriptDirectory.from_config(config).get_heads()
    if len(heads) != 1:
        raise RuntimeError("部署要求 Alembic 只能存在一个迁移 Head")
    return heads[0]


class InfrastructureReadinessProbe:
    """使用短超时检查生产运行所需的基础设施。"""

    def __init__(self, settings: Settings) -> None:
        self._settings = settings

    def check(self) -> ReadinessChecks:
        database_status: Literal["ok", "error"] = "error"
        migration_status: Literal["ok", "error"] = "error"
        redis_status: Literal["ok", "error"] = "error"

        try:
            with get_engine().connect() as connection:
                connection.execute(text("SELECT 1"))
                database_status = "ok"
                versions = set(
                    connection.execute(
                        text("SELECT version_num FROM alembic_version")
                    ).scalars()
                )
                if versions == {_expected_migration_head()}:
                    migration_status = "ok"
        except Exception:
            # 就绪接口只返回稳定状态，不泄露数据库异常或连接信息。
            pass

        redis_client = redis.Redis.from_url(
            self._settings.redis_url,
            socket_connect_timeout=2,
            socket_timeout=2,
        )
        try:
            if redis_client.ping():
                redis_status = "ok"
        except Exception:
            # 生产环境 Redis 故障时保持失败关闭。
            pass
        finally:
            redis_client.close()

        return ReadinessChecks(
            database=database_status,
            redis=redis_status,
            migration=migration_status,
        )


def get_readiness_probe(
    settings: Annotated[Settings, Depends(get_settings)],
) -> ReadinessProbe:
    """为当前环境创建就绪探针。"""
    return InfrastructureReadinessProbe(settings)


@router.get(
    "/healthz",
    response_model=HealthResponse,
    summary="服务存活检查",
    description="仅确认 HTTP 服务进程可响应，不代表数据库或第三方服务已连接。",
)
def health_check(
    settings: Annotated[Settings, Depends(get_settings)],
) -> HealthResponse:
    """返回不含敏感配置的进程状态。"""
    return HealthResponse(
        status="ok",
        service=settings.app_name,
        environment=settings.app_env,
    )


@router.get(
    "/readyz",
    response_model=ReadinessResponse,
    responses={status.HTTP_503_SERVICE_UNAVAILABLE: {"model": ReadinessResponse}},
    summary="服务就绪检查",
    description="检查数据库、Redis 和迁移版本，不返回连接地址或异常正文。",
)
def readiness_check(
    response: Response,
    settings: Annotated[Settings, Depends(get_settings)],
    probe: Annotated[ReadinessProbe, Depends(get_readiness_probe)],
) -> ReadinessResponse:
    """只有所有生产依赖可用且迁移匹配时才返回就绪。"""
    checks = probe.check()
    is_ready = all(
        check_status == "ok"
        for check_status in (checks.database, checks.redis, checks.migration)
    )
    if not is_ready:
        response.status_code = status.HTTP_503_SERVICE_UNAVAILABLE
    return ReadinessResponse(
        status="ready" if is_ready else "not_ready",
        service=settings.app_name,
        environment=settings.app_env,
        version=settings.app_version,
        checks=checks,
    )
