from __future__ import annotations

import asyncio
from dataclasses import dataclass
from uuid import uuid4

import pytest
import sqlalchemy as sa
from pydantic import ValidationError
from sqlalchemy.orm import Session

from app.core.config import Settings
from app.db.base import Base
from app.main import create_app
from app.models import User
from app.services.profile_proposal import (
    ProfileProposalModelResult,
    ProfileProposalRequest,
    ProfileProposalService,
)


@dataclass
class FakeProfileProposalClient:
    calls: int = 0

    async def generate(
        self,
        request: ProfileProposalRequest,
    ) -> ProfileProposalModelResult:
        self.calls += 1
        return ProfileProposalModelResult.model_validate(
            {
                "proposed_fields": [
                    {
                        "field_code": "primary_sport",
                        "value": "running",
                        "confidence": 0.82,
                    },
                ],
                "missing_field_codes": ["equipment_access"],
                "follow_up_codes": [
                    "ask_equipment",
                    "ask_frequency",
                    "ask_duration",
                    "ask_goal",
                    "ask_experience",
                    "ask_primary_sport",
                ],
                "input_tokens": 100,
                "output_tokens": 60,
            },
        )


def _request(*, ambiguity_fragments: list[str]) -> ProfileProposalRequest:
    return ProfileProposalRequest.model_validate(
        {
            "contract_version": 1,
            "request_id": "profile-proposal-1",
            "known_fields": {
                "goal": "fat_loss",
                "weekly_training_days": 3,
                "available_minutes": 40,
            },
            "unresolved_field_codes": [
                "primary_sport",
                "experience_level",
                "equipment_access",
            ],
            "ambiguity_fragments": ambiguity_fragments,
        },
    )


@pytest.mark.parametrize(
    "sensitive_text",
    [
        "我膝盖疼，想试试跑步",
        "我的手机号是 13800138000",
        "我今年 32 岁",
        "体重 80kg，先做有氧",
    ],
)
def test_request_rejects_sensitive_original_text(sensitive_text: str) -> None:
    with pytest.raises(ValidationError):
        _request(ambiguity_fragments=[sensitive_text])


def test_empty_ambiguity_uses_local_fallback_without_model_call() -> None:
    engine = sa.create_engine("sqlite+pysqlite://")
    Base.metadata.create_all(engine)
    user_id = uuid4()
    client = FakeProfileProposalClient()
    with Session(engine) as session:
        session.add(
            User(
                id=user_id,
                email_hash=f"hash-{user_id}",
                masked_email="t***@example.com",
            ),
        )
        session.commit()
        service = ProfileProposalService(
            session=session,
            settings=Settings(),
            client=client,
        )

        artifact, cache_hit = asyncio.run(
            service.propose(user_id, _request(ambiguity_fragments=[])),
        )

    assert cache_hit is False
    assert client.calls == 0
    assert artifact.decision_status == "pending"
    assert artifact.payload["generation_meta"]["generation_mode"] == (
        "local_safe_fallback"
    )
    assert artifact.payload["generation_meta"]["input_tokens"] == 0
    Base.metadata.drop_all(engine)
    engine.dispose()


def test_ambiguous_fragment_returns_pending_bounded_proposal() -> None:
    engine = sa.create_engine("sqlite+pysqlite://")
    Base.metadata.create_all(engine)
    user_id = uuid4()
    client = FakeProfileProposalClient()
    with Session(engine) as session:
        session.add(
            User(
                id=user_id,
                email_hash=f"hash-{user_id}",
                masked_email="t***@example.com",
            ),
        )
        session.commit()
        service = ProfileProposalService(
            session=session,
            settings=Settings(),
            client=client,
        )

        artifact, cache_hit = asyncio.run(
            service.propose(
                user_id,
                _request(ambiguity_fragments=["更喜欢户外耐力类项目"]),
            ),
        )

    assert cache_hit is False
    assert client.calls == 1
    assert artifact.decision_status == "pending"
    assert len(artifact.payload["follow_up_codes"]) <= 5
    assert artifact.payload["proposed_fields"][0]["field_code"] == "primary_sport"
    Base.metadata.drop_all(engine)
    engine.dispose()


def test_profile_proposal_route_is_exposed() -> None:
    paths = create_app().openapi()["paths"]

    assert "/v1/ai/profile-proposals" in paths
    assert "201" in paths["/v1/ai/profile-proposals"]["post"]["responses"]
