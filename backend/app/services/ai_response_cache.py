from __future__ import annotations

import asyncio
import hashlib
import json
import secrets
import time
from collections.abc import Awaitable, Callable
from typing import Any, Protocol

import redis.asyncio as async_redis
from redis.exceptions import RedisError

_CACHE_NAMESPACE = "trainmate:ai-response:v2"
_RELEASE_LOCK_SCRIPT = """
if redis.call("get", KEYS[1]) == ARGV[1] then
  return redis.call("del", KEYS[1])
end
return 0
"""


class AsyncRedisClient(Protocol):
    async def get(self, name: str) -> Any: ...

    async def set(
        self,
        name: str,
        value: str,
        *,
        ex: int | None = None,
        nx: bool = False,
    ) -> Any: ...

    async def eval(
        self,
        script: str,
        numkeys: int,
        *keys_and_args: str,
    ) -> Any: ...


def build_ai_response_cache_key(
    *,
    capability: str,
    model: str,
    prompt_contract_version: str,
    skill_hash: str,
    knowledge_version: str,
    context_digest: str,
    user_domain_hash: str = "",
) -> str:
    """缓存键只保留规范化摘要，不包含用户正文或健康字段。"""
    material = {
        "capability": capability,
        "model": model,
        "prompt_contract_version": prompt_contract_version,
        "skill_hash": skill_hash,
        "knowledge_version": knowledge_version,
        "context_digest": context_digest,
        "user_domain_hash": user_domain_hash,
    }
    encoded = json.dumps(
        material,
        ensure_ascii=True,
        sort_keys=True,
        separators=(",", ":"),
    )
    digest = hashlib.sha256(encoded.encode("utf-8")).hexdigest()
    return f"{_CACHE_NAMESPACE}:{digest}"


def cache_user_domain(user_id: object) -> str:
    """将用户域转换为不可逆缓存分区标识。"""
    return hashlib.sha256(str(user_id).encode("utf-8")).hexdigest()


class AiResponseCache:
    """Redis 尽力缓存加进程内/跨进程 single-flight。"""

    def __init__(
        self,
        redis_url: str | None = None,
        *,
        redis_client: AsyncRedisClient | None = None,
        lock_ttl_seconds: int = 65,
        poll_interval_seconds: float = 0.05,
    ) -> None:
        if redis_client is None and redis_url is None:
            raise ValueError("必须提供 Redis 地址或客户端。")
        self._redis: AsyncRedisClient = redis_client or async_redis.Redis.from_url(
            redis_url,
            decode_responses=True,
            socket_connect_timeout=0.3,
            socket_timeout=0.3,
        )
        self._lock_ttl_seconds = lock_ttl_seconds
        self._poll_interval_seconds = poll_interval_seconds
        self._inflight: dict[str, asyncio.Task[tuple[dict[str, Any], bool]]] = {}
        self._guard = asyncio.Lock()

    async def get_or_compute(
        self,
        *,
        key: str,
        ttl_seconds: int,
        producer: Callable[[], Awaitable[dict[str, Any]]],
    ) -> tuple[dict[str, Any], bool]:
        """返回结果和应用缓存命中标志；Redis 故障时直接旁路。"""
        available, cached = await self._read(key)
        if available and cached is not None:
            return cached, True

        async with self._guard:
            task = self._inflight.get(key)
            joined_existing = task is not None
            if task is None:
                task = asyncio.create_task(
                    self._compute_with_distributed_lock(
                        key=key,
                        ttl_seconds=ttl_seconds,
                        producer=producer,
                    ),
                )
                self._inflight[key] = task
        try:
            value, remote_cache_hit = await task
            return value, joined_existing or remote_cache_hit
        finally:
            if task.done():
                async with self._guard:
                    if self._inflight.get(key) is task:
                        self._inflight.pop(key, None)

    async def _compute_with_distributed_lock(
        self,
        *,
        key: str,
        ttl_seconds: int,
        producer: Callable[[], Awaitable[dict[str, Any]]],
    ) -> tuple[dict[str, Any], bool]:
        available, cached = await self._read(key)
        if available and cached is not None:
            return cached, True

        lock_key = f"{key}:lock"
        owner = secrets.token_hex(16)
        acquired = await self._acquire_lock(lock_key, owner)
        if acquired is None:
            return await producer(), False
        if not acquired:
            deadline = time.monotonic() + self._lock_ttl_seconds + 1
            while time.monotonic() < deadline:
                await asyncio.sleep(self._poll_interval_seconds)
                available, cached = await self._read(key)
                if not available:
                    return await producer(), False
                if cached is not None:
                    return cached, True
            acquired = await self._acquire_lock(lock_key, owner)
            if not acquired:
                return await producer(), False

        try:
            value = await producer()
            await self._write(key, value, ttl_seconds)
            return value, False
        finally:
            await self._release_lock(lock_key, owner)

    async def _read(self, key: str) -> tuple[bool, dict[str, Any] | None]:
        try:
            raw = await self._redis.get(key)
        except (RedisError, OSError, TimeoutError):
            return False, None
        if raw is None:
            return True, None
        try:
            if isinstance(raw, bytes):
                raw = raw.decode("utf-8")
            value = json.loads(raw)
        except (UnicodeDecodeError, TypeError, ValueError):
            return True, None
        return (True, value) if isinstance(value, dict) else (True, None)

    async def _write(
        self,
        key: str,
        value: dict[str, Any],
        ttl_seconds: int,
    ) -> None:
        try:
            encoded = json.dumps(
                value,
                ensure_ascii=False,
                sort_keys=True,
                separators=(",", ":"),
            )
            await self._redis.set(key, encoded, ex=ttl_seconds)
        except (RedisError, OSError, TimeoutError, TypeError, ValueError):
            return

    async def _acquire_lock(self, lock_key: str, owner: str) -> bool | None:
        try:
            result = await self._redis.set(
                lock_key,
                owner,
                ex=self._lock_ttl_seconds,
                nx=True,
            )
            return bool(result)
        except (RedisError, OSError, TimeoutError):
            return None

    async def _release_lock(self, lock_key: str, owner: str) -> None:
        try:
            await self._redis.eval(_RELEASE_LOCK_SCRIPT, 1, lock_key, owner)
        except (RedisError, OSError, TimeoutError):
            return
