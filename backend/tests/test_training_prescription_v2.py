from __future__ import annotations

import asyncio
from dataclasses import dataclass
from uuid import uuid4

import sqlalchemy as sa
from sqlalchemy.orm import Session

from app.core.config import Settings
from app.core.errors import ApiError
from app.db.base import Base
from app.main import create_app
from app.models import User
from app.services.ai_generation import AiArtifactService
from app.services.ai_response_cache import AiResponseCache
from app.services.knowledge_catalog import (
    KNOWLEDGE_CATALOG_VERSION,
    KnowledgeCatalogService,
    KnowledgeRetrievalResult,
)
from app.services.training_prescription import (
    TrainingPrescriptionModelResult,
    TrainingPrescriptionRequest,
    TrainingSessionBlueprint,
    ValidatedTrainingPrescription,
)
from app.services.training_prescription_v2 import (
    TrainingPrescriptionV2Request,
    TrainingPrescriptionV2Service,
)
from app.services.training_skills import SkillSelection, TrainingSkillRegistry


@dataclass
class FakeKnowledgeAwareClient:
    calls: int = 0

    async def generate(
        self,
        request: TrainingPrescriptionRequest,
        selection: SkillSelection,
    ) -> TrainingPrescriptionModelResult:
        del request, selection
        self.calls += 1
        raise AssertionError("唯一模板不应调用模型")

    async def generate_with_knowledge(
        self,
        request: TrainingPrescriptionRequest,
        selection: SkillSelection,
        retrieval: KnowledgeRetrievalResult,
    ) -> TrainingPrescriptionModelResult:
        del request, selection, retrieval
        self.calls += 1
        raise AssertionError("唯一模板不应调用模型")


class FailingKnowledgeClient(FakeKnowledgeAwareClient):
    async def generate_with_knowledge(
        self,
        request: TrainingPrescriptionRequest,
        selection: SkillSelection,
        retrieval: KnowledgeRetrievalResult,
    ) -> TrainingPrescriptionModelResult:
        del request, selection, retrieval
        self.calls += 1
        raise ApiError(503, "deepseek_not_configured", "AI 服务尚未配置")


@dataclass
class CloudKnowledgeClient(FakeKnowledgeAwareClient):
    async def generate_with_knowledge(
        self,
        request: TrainingPrescriptionRequest,
        selection: SkillSelection,
        retrieval: KnowledgeRetrievalResult,
    ) -> TrainingPrescriptionModelResult:
        del selection, retrieval
        self.calls += 1
        pattern = ["easy_run", "strength", "hyrox", "mobility", "easy_run"]
        return TrainingPrescriptionModelResult(
            prescription=ValidatedTrainingPrescription(
                cycle_focus="base",
                weekly_sessions=[
                    TrainingSessionBlueprint(
                        training_type=training_type,
                        duration_minutes=request.context.available_minutes,
                        intensity_band=(
                            "easy"
                            if training_type in {"easy_run", "mobility"}
                            else "moderate"
                        ),
                        focus_codes=[
                            {
                                "easy_run": "aerobic_base",
                                "strength": "full_body_strength",
                                "hyrox": "hyrox_transition",
                                "mobility": "mobility",
                            }[training_type],
                        ],
                    )
                    for training_type in pattern
                ],
                progression_mode="balanced",
            ),
            input_tokens=240,
            output_tokens=90,
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


def test_v2_route_keeps_v1_and_exposes_pending_artifact_contract() -> None:
    paths = create_app().openapi()["paths"]

    assert "/v1/ai/training-prescriptions" in paths
    assert "/v2/ai/training-prescriptions" in paths
    responses = paths["/v2/ai/training-prescriptions"]["post"]["responses"]
    assert "201" in responses


def test_v2_unique_template_returns_pending_artifact_without_model_call() -> None:
    engine = sa.create_engine("sqlite+pysqlite://")
    Base.metadata.create_all(engine)
    user_id = uuid4()
    client = FakeKnowledgeAwareClient()
    with Session(engine) as session:
        session.add(
            User(
                id=user_id,
                email_hash=f"hash-{user_id}",
                masked_email="t***@example.com",
            ),
        )
        session.commit()
        knowledge = KnowledgeCatalogService(session)
        knowledge.ensure_seeded()
        service = TrainingPrescriptionV2Service(
            session=session,
            settings=Settings(training_structure_v1_enabled=True),
            registry=TrainingSkillRegistry.default(),
            client=client,
            knowledge=knowledge,
        )
        request = TrainingPrescriptionV2Request.model_validate(
            {
                "contract_version": 2,
                "client_context_digest": "a" * 64,
                "population_template_id": "low_impact_fat_loss",
                "knowledge_snapshot_version": KNOWLEDGE_CATALOG_VERSION,
                "context": {
                    "goal": "fat_loss",
                    "primary_sport": "general_fitness",
                    "experience_level": "beginner",
                    "weekly_training_days": 3,
                    "available_minutes": 40,
                    "equipment_access": ["bodyweight", "dumbbell"],
                },
            },
        )

        artifact, cache_hit = asyncio.run(service.generate(user_id, request))
        session.refresh(artifact)
        payload = artifact.payload
        decision_status = artifact.decision_status

    assert cache_hit is False
    assert client.calls == 0
    assert decision_status == "pending"
    assert payload["generation_meta"]["generation_mode"] == "local_template"
    assert payload["generation_meta"]["input_tokens"] == 0
    assert payload["generation_meta"]["contract_version"] == 2
    assert payload["generation_meta"]["client_context_digest"] == "a" * 64
    assert payload["generation_meta"]["model"] == "deterministic-template-v1"
    assert (
        payload["generation_meta"]["structure_policy_version"]
        == "training-structure-v1"
    )
    first_structure = payload["weekly_sessions"][0]["structure_profile"]
    assert first_structure["primary_dimension_codes"] == [
        "stability",
        "breathing",
    ]
    assert len(first_structure["primary_dimension_codes"]) <= 2
    assert "leg_element_codes" in first_structure
    assert payload["applied_skill"]["display_name"]
    assert payload["selection_reason_code"]
    assert payload["knowledge_citations"]
    assert payload["knowledge_citations"][-1]["id"] == "low_impact_fat_loss_3d"
    Base.metadata.drop_all(engine)
    engine.dispose()


def test_v2_structure_backfill_defaults_to_disabled() -> None:
    settings = Settings()

    assert settings.training_structure_v1_enabled is False


def test_v2_cloud_failure_returns_local_safe_pending_artifact() -> None:
    engine = sa.create_engine("sqlite+pysqlite://")
    Base.metadata.create_all(engine)
    user_id = uuid4()
    client = FailingKnowledgeClient()
    with Session(engine) as session:
        session.add(
            User(
                id=user_id,
                email_hash=f"hash-{user_id}",
                masked_email="t***@example.com",
            ),
        )
        session.commit()
        knowledge = KnowledgeCatalogService(session)
        knowledge.ensure_seeded()
        service = TrainingPrescriptionV2Service(
            session=session,
            settings=Settings(),
            registry=TrainingSkillRegistry.default(),
            client=client,
            knowledge=knowledge,
        )
        request = TrainingPrescriptionV2Request.model_validate(
            {
                "contract_version": 2,
                "client_context_digest": "b" * 64,
                "population_template_id": "sedentary_beginner",
                "knowledge_snapshot_version": KNOWLEDGE_CATALOG_VERSION,
                "context": {
                    "goal": "general_fitness",
                    "primary_sport": "general_fitness",
                    "experience_level": "beginner",
                    "weekly_training_days": 4,
                    "available_minutes": 30,
                    "equipment_access": ["bodyweight"],
                },
            },
        )

        artifact, cache_hit = asyncio.run(service.generate(user_id, request))
        payload = artifact.payload

    assert cache_hit is False
    assert client.calls == 1
    assert artifact.decision_status == "pending"
    assert payload["generation_meta"]["generation_mode"] == ("local_safe_fallback")
    assert payload["generation_meta"]["input_tokens"] == 0
    assert len(payload["weekly_sessions"]) == 4
    Base.metadata.drop_all(engine)
    engine.dispose()


def test_v2_enumerated_cloud_result_reuses_cross_user_cache() -> None:
    engine = sa.create_engine("sqlite+pysqlite://")
    Base.metadata.create_all(engine)
    first_user_id = uuid4()
    second_user_id = uuid4()
    client = CloudKnowledgeClient()
    response_cache = AiResponseCache(redis_client=InMemoryAsyncRedis())
    with Session(engine) as session:
        session.add_all(
            [
                User(
                    id=first_user_id,
                    email_hash=f"hash-{first_user_id}",
                    masked_email="a***@example.com",
                ),
                User(
                    id=second_user_id,
                    email_hash=f"hash-{second_user_id}",
                    masked_email="b***@example.com",
                ),
            ],
        )
        session.commit()
        knowledge = KnowledgeCatalogService(session)
        knowledge.ensure_seeded()
        service = TrainingPrescriptionV2Service(
            session=session,
            settings=Settings(),
            registry=TrainingSkillRegistry.default(),
            client=client,
            knowledge=knowledge,
            response_cache=response_cache,
        )
        request = TrainingPrescriptionV2Request.model_validate(
            {
                "contract_version": 2,
                "client_context_digest": "d" * 64,
                "population_template_id": "hyrox_hybrid",
                "knowledge_snapshot_version": KNOWLEDGE_CATALOG_VERSION,
                "context": {
                    "goal": "endurance",
                    "primary_sport": "hyrox",
                    "experience_level": "intermediate",
                    "weekly_training_days": 5,
                    "available_minutes": 45,
                    "equipment_access": ["bodyweight", "sled"],
                },
            },
        )

        first, first_cache_hit = asyncio.run(
            service.generate(first_user_id, request),
        )
        second, second_cache_hit = asyncio.run(
            service.generate(second_user_id, request),
        )
        first_artifact_user_id = first.user_id
        second_artifact_user_id = second.user_id
        second_input_tokens = second.payload["generation_meta"]["input_tokens"]

    assert client.calls == 1
    assert first_cache_hit is False
    assert second_cache_hit is True
    assert first_artifact_user_id == first_user_id
    assert second_artifact_user_id == second_user_id
    assert second_input_tokens == 0
    Base.metadata.drop_all(engine)
    engine.dispose()


def test_v2_acceptance_rejects_unknown_knowledge_citation() -> None:
    engine = sa.create_engine("sqlite+pysqlite://")
    Base.metadata.create_all(engine)
    user_id = uuid4()
    client = FakeKnowledgeAwareClient()
    with Session(engine) as session:
        session.add(
            User(
                id=user_id,
                email_hash=f"hash-{user_id}",
                masked_email="t***@example.com",
            ),
        )
        session.commit()
        knowledge = KnowledgeCatalogService(session)
        knowledge.ensure_seeded()
        service = TrainingPrescriptionV2Service(
            session=session,
            settings=Settings(),
            registry=TrainingSkillRegistry.default(),
            client=client,
            knowledge=knowledge,
        )
        request = TrainingPrescriptionV2Request.model_validate(
            {
                "contract_version": 2,
                "client_context_digest": "c" * 64,
                "population_template_id": "low_impact_fat_loss",
                "knowledge_snapshot_version": KNOWLEDGE_CATALOG_VERSION,
                "context": {
                    "goal": "fat_loss",
                    "primary_sport": "general_fitness",
                    "experience_level": "beginner",
                    "weekly_training_days": 3,
                    "available_minutes": 40,
                    "equipment_access": ["bodyweight", "dumbbell"],
                },
            },
        )
        artifact, _ = asyncio.run(service.generate(user_id, request))
        payload = dict(artifact.payload)
        payload["knowledge_citations"] = [
            {
                "id": "retired-or-invented",
                "type": "principle",
                "title": "无效引用",
                "source_label": "无效来源",
                "source_section": "无效章节",
            },
        ]
        artifact.payload = payload
        session.commit()

        artifact_service = AiArtifactService(
            session,
            Settings(),
            object(),  # type: ignore[arg-type]
            object(),  # type: ignore[arg-type]
        )
        try:
            artifact_service.decide(user_id, artifact.id, "accepted")
        except ApiError as error:
            assert error.code == "training_plan_skill_unavailable"
        else:
            raise AssertionError("未知或停用知识引用必须阻止处方确认")

    Base.metadata.drop_all(engine)
    engine.dispose()
