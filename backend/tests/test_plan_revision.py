from __future__ import annotations

import asyncio
from dataclasses import dataclass
from uuid import uuid4

import sqlalchemy as sa
from pydantic import ValidationError
from sqlalchemy.orm import Session

from app.core.config import Settings
from app.core.errors import ApiError
from app.db.base import Base
from app.main import create_app
from app.models import User
from app.services.ai_generation import AiArtifactService
from app.services.plan_revision import (
    PlanRevisionModelResult,
    PlanRevisionRequest,
    PlanRevisionService,
)


@dataclass
class FailingPlanRevisionClient:
    calls: int = 0

    async def generate(
        self,
        request: PlanRevisionRequest,
    ) -> PlanRevisionModelResult:
        del request
        self.calls += 1
        raise ApiError(503, "deepseek_not_configured", "AI 服务尚未配置")


def _request(**overrides: object) -> PlanRevisionRequest:
    payload: dict[str, object] = {
        "contract_version": 1,
        "client_context_digest": "a" * 64,
        "remaining_dates": ["2026-08-01", "2026-08-03", "2026-08-05"],
        "completion_summary": {
            "completed_sessions": 3,
            "missed_sessions": 2,
        },
        "schedule_change_dates": ["2026-08-03", "2026-08-05"],
        "available_minutes": 40,
        "equipment_access": ["bodyweight", "dumbbell"],
        "equipment_changed": True,
        "safety_constraint_codes": ["no_increase"],
        "current_prescription": {
            "cycle_focus": "base",
            "weekly_sessions": [
                {
                    "training_type": "strength",
                    "duration_minutes": 45,
                    "intensity_band": "moderate",
                    "focus_codes": ["full_body_strength"],
                },
                {
                    "training_type": "easy_run",
                    "duration_minutes": 40,
                    "intensity_band": "easy",
                    "focus_codes": ["aerobic_base"],
                },
            ],
            "progression_mode": "conservative",
        },
    }
    payload.update(overrides)
    return PlanRevisionRequest.model_validate(payload)


def test_plan_revision_route_exists_and_request_rejects_health_reason() -> None:
    paths = create_app().openapi()["paths"]
    assert "/v1/ai/plan-revisions" in paths

    try:
        _request(health_reason="膝痛")
    except ValidationError:
        pass
    else:
        raise AssertionError("周期重排请求不得接收健康原因字段")


def test_plan_revision_cloud_failure_returns_pending_local_safe_artifact() -> None:
    engine = sa.create_engine("sqlite+pysqlite://")
    Base.metadata.create_all(engine)
    user_id = uuid4()
    client = FailingPlanRevisionClient()
    with Session(engine) as session:
        session.add(
            User(
                id=user_id,
                email_hash=f"hash-{user_id}",
                masked_email="t***@example.com",
            ),
        )
        session.commit()
        service = PlanRevisionService(
            session=session,
            settings=Settings(),
            client=client,
        )

        artifact, cache_hit = asyncio.run(service.generate(user_id, _request()))
        payload = artifact.payload

        assert cache_hit is False
        assert client.calls == 1
        assert artifact.decision_status == "pending"
        assert artifact.artifact_type == "plan_revision_v1"
        assert payload["generation_meta"]["generation_mode"] == (
            "local_safe_fallback"
        )
        assert payload["generation_meta"]["input_tokens"] == 0
        assert payload["differences"]
        encoded = str(payload)
        assert "膝痛" not in encoded
        assert "health_reason" not in encoded

        artifact_service = AiArtifactService(
            session,
            Settings(),
            object(),  # type: ignore[arg-type]
            object(),  # type: ignore[arg-type]
        )
        accepted = artifact_service.decide(user_id, artifact.id, "accepted")
        assert accepted.decision_status == "accepted"
        try:
            artifact_service.decide(user_id, artifact.id, "rejected")
        except ApiError as error:
            assert error.code == "plan_revision_decision_conflict"
        else:
            raise AssertionError("已确认重排不得改为拒绝")

    Base.metadata.drop_all(engine)
    engine.dispose()
