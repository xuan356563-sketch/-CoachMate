from __future__ import annotations

from datetime import timedelta
from typing import Any

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.security import utc_now
from app.models import (
    AccountDeletionRequest,
    AiUsageEvent,
    SyncChange,
    SyncMutation,
    User,
)


class OpsMetricsService:
    """只生成聚合运维指标，不返回账号或训练明细。"""

    def __init__(self, session: Session) -> None:
        self._session = session

    def summary(self) -> dict[str, int]:
        since = utc_now() - timedelta(hours=24)
        return {
            "users_total": self._count(User),
            "synced_users_total": int(
                self._session.scalar(
                    select(func.count(func.distinct(SyncMutation.user_id))),
                )
                or 0
            ),
            "sync_conflicts_24h": self._sync_conflicts_since(since),
            "ai_requests_24h": int(
                self._session.scalar(
                    select(func.count())
                    .select_from(AiUsageEvent)
                    .where(AiUsageEvent.created_at >= since),
                )
                or 0
            ),
            "deletion_pending": int(
                self._session.scalar(
                    select(func.count())
                    .select_from(AccountDeletionRequest)
                    .where(AccountDeletionRequest.status == "pending"),
                )
                or 0
            ),
        }

    def sync_health(self) -> dict[str, Any]:
        since = utc_now() - timedelta(hours=24)
        latest_cursor = self._session.scalar(select(func.max(SyncChange.cursor)))
        latest_mutation_at = self._session.scalar(
            select(func.max(SyncMutation.created_at)),
        )
        return {
            "mutations_24h": int(
                self._session.scalar(
                    select(func.count())
                    .select_from(SyncMutation)
                    .where(SyncMutation.created_at >= since),
                )
                or 0
            ),
            "conflicts_24h": self._sync_conflicts_since(since),
            "latest_cursor": int(latest_cursor or 0),
            "latest_mutation_at": (
                latest_mutation_at.isoformat()
                if latest_mutation_at is not None
                else None
            ),
        }

    def ai_usage(self) -> dict[str, list[dict[str, Any]]]:
        since = utc_now() - timedelta(hours=24)
        rows = self._session.execute(
            select(
                AiUsageEvent.provider,
                AiUsageEvent.model,
                AiUsageEvent.capability,
                AiUsageEvent.prompt_contract_version,
                AiUsageEvent.result_code,
                func.count(AiUsageEvent.id),
                func.coalesce(func.sum(AiUsageEvent.input_tokens), 0),
                func.coalesce(func.sum(AiUsageEvent.output_tokens), 0),
                func.coalesce(
                    func.sum(AiUsageEvent.prompt_cache_hit_tokens),
                    0,
                ),
                func.coalesce(
                    func.sum(AiUsageEvent.prompt_cache_miss_tokens),
                    0,
                ),
                func.coalesce(func.avg(AiUsageEvent.latency_ms), 0),
            )
            .where(AiUsageEvent.created_at >= since)
            .group_by(
                AiUsageEvent.provider,
                AiUsageEvent.model,
                AiUsageEvent.capability,
                AiUsageEvent.prompt_contract_version,
                AiUsageEvent.result_code,
            )
            .order_by(
                AiUsageEvent.provider,
                AiUsageEvent.model,
                AiUsageEvent.capability,
                AiUsageEvent.prompt_contract_version,
                AiUsageEvent.result_code,
            ),
        ).all()
        return {
            "groups": [
                {
                    "provider": provider,
                    "model": model,
                    "capability": capability,
                    "prompt_contract_version": prompt_contract_version,
                    "result_code": result_code,
                    "requests": int(requests),
                    "input_tokens": int(input_tokens),
                    "output_tokens": int(output_tokens),
                    "prompt_cache_hit_tokens": int(prompt_cache_hit_tokens),
                    "prompt_cache_miss_tokens": int(prompt_cache_miss_tokens),
                    "average_latency_ms": round(float(average_latency_ms)),
                }
                for (
                    provider,
                    model,
                    capability,
                    prompt_contract_version,
                    result_code,
                    requests,
                    input_tokens,
                    output_tokens,
                    prompt_cache_hit_tokens,
                    prompt_cache_miss_tokens,
                    average_latency_ms,
                ) in rows
            ],
        }

    def deletion_jobs(self) -> dict[str, Any]:
        rows = self._session.execute(
            select(
                AccountDeletionRequest.status,
                func.count(AccountDeletionRequest.id),
            ).group_by(AccountDeletionRequest.status),
        ).all()
        counts = {status: int(count) for status, count in rows}
        next_due_at = self._session.scalar(
            select(func.min(AccountDeletionRequest.purge_after)).where(
                AccountDeletionRequest.status == "pending",
            ),
        )
        return {
            "pending": counts.get("pending", 0),
            "cancelled": counts.get("cancelled", 0),
            "next_due_at": (
                next_due_at.isoformat() if next_due_at is not None else None
            ),
        }

    def _sync_conflicts_since(self, since) -> int:
        return int(
            self._session.scalar(
                select(func.count())
                .select_from(SyncMutation)
                .where(
                    SyncMutation.outcome == "conflict",
                    SyncMutation.created_at >= since,
                ),
            )
            or 0
        )

    def _count(self, model) -> int:
        return int(
            self._session.scalar(select(func.count()).select_from(model)) or 0
        )
