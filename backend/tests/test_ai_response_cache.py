from __future__ import annotations

import asyncio
import json
from collections.abc import Awaitable
from typing import Any

import redis

from app.services.ai_response_cache import (
    AiResponseCache,
    build_ai_response_cache_key,
    cache_user_domain,
)


class InMemoryAsyncRedis:
    def __init__(self) -> None:
        self.values: dict[str, str] = {}

    async def get(self, name: str) -> str | None:
        return self.values.get(name)

    async def set(
        self,
        name: str,
        value: str,
        *,
        ex: int | None = None,
        nx: bool = False,
    ) -> bool:
        del ex
        if nx and name in self.values:
            return False
        self.values[name] = value
        return True

    async def eval(
        self,
        script: str,
        numkeys: int,
        *keys_and_args: str,
    ) -> int:
        del script, numkeys
        key, owner = keys_and_args
        if self.values.get(key) != owner:
            return 0
        self.values.pop(key, None)
        return 1


class FailingAsyncRedis(InMemoryAsyncRedis):
    async def get(self, name: str) -> str | None:
        del name
        raise redis.ConnectionError("测试 Redis 不可用")

    async def set(
        self,
        name: str,
        value: str,
        *,
        ex: int | None = None,
        nx: bool = False,
    ) -> bool:
        del name, value, ex, nx
        raise redis.ConnectionError("测试 Redis 不可用")


def _run(coroutine: Awaitable[Any]) -> Any:
    return asyncio.run(coroutine)


def test_same_digest_concurrency_only_invokes_producer_once() -> None:
    async def scenario() -> tuple[int, list[tuple[dict[str, Any], bool]]]:
        cache = AiResponseCache(
            redis_client=InMemoryAsyncRedis(),
            poll_interval_seconds=0.001,
        )
        calls = 0

        async def producer() -> dict[str, Any]:
            nonlocal calls
            calls += 1
            await asyncio.sleep(0.01)
            return {"result": "ok"}

        results = await asyncio.gather(
            *[
                cache.get_or_compute(
                    key="same-key",
                    ttl_seconds=60,
                    producer=producer,
                )
                for _ in range(8)
            ],
        )
        return calls, results

    calls, results = _run(scenario())
    assert calls == 1
    assert sum(1 for _, cache_hit in results if not cache_hit) == 1
    assert all(value == {"result": "ok"} for value, _ in results)


def test_redis_failure_bypasses_cache_but_keeps_local_single_flight() -> None:
    async def scenario() -> tuple[int, list[tuple[dict[str, Any], bool]]]:
        cache = AiResponseCache(redis_client=FailingAsyncRedis())
        calls = 0

        async def producer() -> dict[str, Any]:
            nonlocal calls
            calls += 1
            await asyncio.sleep(0.01)
            return {"fallback": True}

        results = await asyncio.gather(
            cache.get_or_compute(
                key="redis-down",
                ttl_seconds=60,
                producer=producer,
            ),
            cache.get_or_compute(
                key="redis-down",
                ttl_seconds=60,
                producer=producer,
            ),
        )
        return calls, results

    calls, results = _run(scenario())
    assert calls == 1
    assert results[0][0] == {"fallback": True}
    assert results[1][1] is True


def test_cache_key_contains_versions_but_not_raw_context() -> None:
    key = build_ai_response_cache_key(
        capability="profile_proposal",
        model="deepseek-v4-flash",
        prompt_contract_version="profile-proposal-v1",
        skill_hash="skill-sha",
        knowledge_version="knowledge-v1",
        context_digest="raw-private-training-preference",
        user_domain_hash=cache_user_domain("user-1"),
    )
    changed = build_ai_response_cache_key(
        capability="profile_proposal",
        model="deepseek-v4-flash",
        prompt_contract_version="profile-proposal-v2",
        skill_hash="skill-sha",
        knowledge_version="knowledge-v1",
        context_digest="raw-private-training-preference",
        user_domain_hash=cache_user_domain("user-1"),
    )
    other_user = build_ai_response_cache_key(
        capability="profile_proposal",
        model="deepseek-v4-flash",
        prompt_contract_version="profile-proposal-v1",
        skill_hash="skill-sha",
        knowledge_version="knowledge-v1",
        context_digest="raw-private-training-preference",
        user_domain_hash=cache_user_domain("user-2"),
    )

    assert key.startswith("trainmate:ai-response:v2:")
    assert "raw-private-training-preference" not in key
    assert "user-1" not in key
    assert key != changed
    assert key != other_user
    assert len(json.dumps({"key": key})) < 160
