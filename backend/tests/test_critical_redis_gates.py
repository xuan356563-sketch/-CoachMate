from __future__ import annotations

import pytest
import redis

from app.core.config import Settings
from app.core.errors import ApiError
from app.services.ai_generation_rate_limit import AiGenerationRateLimiter
from app.services.auth_redis_gate import AuthRedisGate
from app.services.sync_service import SyncWriteGate


def _production_settings() -> Settings:
    return Settings.model_construct(
        app_env="production",
        redis_url="redis://127.0.0.1:1/0",
        ai_generation_window_seconds=600,
        ai_generation_limit=20,
    )


@pytest.mark.parametrize(
    ("gate_factory", "expected_code"),
    [
        (AuthRedisGate, "auth_state_unavailable"),
        (SyncWriteGate, "sync_write_unavailable"),
    ],
)
def test_production_critical_write_gate_fails_closed_when_redis_is_down(
    monkeypatch: pytest.MonkeyPatch,
    gate_factory,
    expected_code: str,
) -> None:
    """将失败关闭改为继续写入时，此测试必须失败。"""
    gate = gate_factory(_production_settings())

    def unavailable() -> None:
        raise redis.ConnectionError("测试连接失败")

    monkeypatch.setattr(gate._redis, "ping", unavailable)

    with pytest.raises(ApiError) as error:
        gate.check()
    assert error.value.status_code == 503
    assert error.value.code == expected_code


def test_production_ai_rate_limit_fails_closed_when_redis_is_down(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Redis 故障时不得绕过 AI 写请求限流。"""
    limiter = AiGenerationRateLimiter(_production_settings())

    def unavailable(_user_id) -> None:
        raise redis.ConnectionError("测试连接失败")

    monkeypatch.setattr(limiter, "_check_redis", unavailable)

    with pytest.raises(ApiError) as error:
        limiter.check("019f4220-5ce2-7082-b418-5d087d24a4a9")
    assert error.value.status_code == 503
    assert error.value.code == "ai_rate_limit_unavailable"
