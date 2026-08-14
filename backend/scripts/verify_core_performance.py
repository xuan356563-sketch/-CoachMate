from __future__ import annotations

import math
import tempfile
from collections.abc import Generator
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from time import perf_counter
from uuid import UUID, uuid4

from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker

from app.api.auth import get_current_access_claims
from app.core.config import Settings, get_settings
from app.core.security import AccessTokenClaims
from app.db.base import Base
from app.db.session import get_session
from app.main import create_app
from app.models import User

NON_AI_P95_LIMIT_MS = 500
SYNC_BATCH_P95_LIMIT_MS = 2_000
CONCURRENT_USERS = 20
SYNC_BATCH_SIZE = 100
SYNC_SAMPLE_COUNT = 10


def _p95(values: list[float]) -> float:
    ordered = sorted(values)
    index = max(0, math.ceil(len(ordered) * 0.95) - 1)
    return ordered[index]


def _completion_batch(sample: int) -> dict[str, object]:
    plan_id = str(uuid4())
    workout_id = str(uuid4())
    return {
        "mutations": [
            {
                "mutation_id": str(uuid4()),
                "entity_type": "completion_summaries",
                "entity_id": str(uuid4()),
                "operation": "upsert",
                "base_version": None,
                "payload": {
                    "plan_version_id": plan_id,
                    "scheduled_workout_id": workout_id,
                    "started_at": f"2026-07-28T{sample:02d}:00:00Z",
                    "ended_at": f"2026-07-28T{sample:02d}:30:00Z",
                    "duration_seconds": 1800,
                    "completion_percentage": 100,
                    "revoked": False,
                },
            }
            for _ in range(SYNC_BATCH_SIZE)
        ],
    }


def run() -> tuple[float, float]:
    """在隔离 SQLite 上测量完整 HTTP、校验和数据库代码路径。"""
    with tempfile.TemporaryDirectory(prefix="trainmate-performance-") as folder:
        database_path = Path(folder) / "performance.db"
        engine = create_engine(
            f"sqlite+pysqlite:///{database_path}",
            connect_args={"check_same_thread": False},
        )
        Base.metadata.create_all(engine)
        session_factory = sessionmaker(bind=engine)
        user_id = uuid4()
        with Session(engine) as session:
            session.add(User(id=user_id, email_hash="性能测试不可逆摘要"))
            session.commit()

        settings = Settings(sync_enabled=True)
        app = create_app()

        def test_session() -> Generator[Session, None, None]:
            with session_factory() as session:
                yield session

        app.dependency_overrides[get_session] = test_session
        app.dependency_overrides[get_settings] = lambda: settings
        app.dependency_overrides[get_current_access_claims] = lambda: (
            AccessTokenClaims(user_id=user_id, session_id=UUID(int=1))
        )

        try:
            with TestClient(app) as client:
                warmup = client.get("/v1/sync/snapshot")
                if warmup.status_code != 200:
                    raise RuntimeError(
                        f"性能预热失败：HTTP {warmup.status_code}",
                    )

                def read_snapshot(_: int) -> float:
                    started = perf_counter()
                    response = client.get("/v1/sync/snapshot")
                    elapsed_ms = (perf_counter() - started) * 1_000
                    if response.status_code != 200:
                        raise RuntimeError(
                            f"并发读取失败：HTTP {response.status_code}",
                        )
                    return elapsed_ms

                with ThreadPoolExecutor(
                    max_workers=CONCURRENT_USERS,
                ) as executor:
                    non_ai_latencies = list(
                        executor.map(read_snapshot, range(CONCURRENT_USERS)),
                    )

                sync_latencies: list[float] = []
                for sample in range(SYNC_SAMPLE_COUNT):
                    started = perf_counter()
                    response = client.post(
                        "/v1/sync/mutations",
                        json=_completion_batch(sample),
                    )
                    elapsed_ms = (perf_counter() - started) * 1_000
                    if response.status_code != 200:
                        raise RuntimeError(
                            f"同步批次失败：HTTP {response.status_code}",
                        )
                    sync_latencies.append(elapsed_ms)
        finally:
            app.dependency_overrides.clear()
            engine.dispose()

    return _p95(non_ai_latencies), _p95(sync_latencies)


def main() -> None:
    non_ai_p95, sync_p95 = run()
    print(f"20 并发非 AI API p95：{non_ai_p95:.1f} ms")
    print(f"100 条同步批次 p95：{sync_p95:.1f} ms")
    if non_ai_p95 >= NON_AI_P95_LIMIT_MS:
        raise SystemExit("非 AI API 未达到 p95 小于 500ms 的门槛")
    if sync_p95 >= SYNC_BATCH_P95_LIMIT_MS:
        raise SystemExit("100 条同步批次未达到 p95 小于 2 秒的门槛")


if __name__ == "__main__":
    main()
