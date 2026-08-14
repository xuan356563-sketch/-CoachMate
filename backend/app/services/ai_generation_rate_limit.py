from __future__ import annotations

from collections import defaultdict, deque
from threading import Lock
from time import monotonic, time
from uuid import UUID

import redis

from app.core.config import Settings
from app.core.errors import ApiError


class AiGenerationRateLimiter:
    """为文本和图片 AI 请求提供按账号限流，生产环境 Redis 故障时拒绝请求。"""

    def __init__(self, settings: Settings) -> None:
        self._settings = settings
        self._redis = redis.Redis.from_url(
            settings.redis_url,
            socket_connect_timeout=1,
            socket_timeout=1,
            decode_responses=True,
        )
        self._memory: dict[str, deque[float]] = defaultdict(deque)
        self._lock = Lock()

    def check(self, user_id: UUID) -> None:
        try:
            self._check_redis(user_id)
        except redis.RedisError as error:
            if self._settings.app_env == "production":
                raise ApiError(
                    503,
                    "ai_rate_limit_unavailable",
                    "AI 服务暂时不可用，请稍后重试",
                ) from error
            self._check_memory(user_id)

    def _check_redis(self, user_id: UUID) -> None:
        bucket = int(time() // self._settings.ai_generation_window_seconds)
        key = f"trainflow:ai:{user_id}:{bucket}"
        pipeline = self._redis.pipeline(transaction=True)
        pipeline.incr(key)
        pipeline.expire(key, self._settings.ai_generation_window_seconds + 5)
        count, _ = pipeline.execute()
        if int(count) > self._settings.ai_generation_limit:
            self._raise_limited()

    def _check_memory(self, user_id: UUID) -> None:
        now = monotonic()
        start = now - self._settings.ai_generation_window_seconds
        key = str(user_id)
        with self._lock:
            timestamps = self._memory[key]
            while timestamps and timestamps[0] < start:
                timestamps.popleft()
            if len(timestamps) >= self._settings.ai_generation_limit:
                self._raise_limited()
            timestamps.append(now)

    @staticmethod
    def _raise_limited() -> None:
        raise ApiError(429, "ai_rate_limited", "AI 请求次数过多，请十分钟后再试")
