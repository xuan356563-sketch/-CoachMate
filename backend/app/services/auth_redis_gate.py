from __future__ import annotations

import redis

from app.core.config import Settings
from app.core.errors import ApiError


class AuthRedisGate:
    """生产环境认证状态写入在 Redis 故障时失败关闭。"""

    def __init__(self, settings: Settings) -> None:
        self._settings = settings
        self._redis = redis.Redis.from_url(
            settings.redis_url,
            socket_connect_timeout=1,
            socket_timeout=1,
            decode_responses=True,
        )

    def check(self) -> None:
        if self._settings.app_env != "production":
            return
        try:
            self._redis.ping()
        except redis.RedisError as error:
            raise ApiError(
                503,
                "auth_state_unavailable",
                "登录与验证码服务暂时不可用，请稍后重试",
            ) from error
