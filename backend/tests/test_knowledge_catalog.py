from __future__ import annotations

from collections.abc import Generator
from uuid import UUID

import sqlalchemy as sa
from fastapi.testclient import TestClient
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool

from app.api.auth import get_current_access_claims
from app.core.security import AccessTokenClaims
from app.db.base import Base
from app.db.session import get_session
from app.main import create_app
from app.models.knowledge import KnowledgePrincipleRecord
from app.services.knowledge_catalog import KnowledgeCatalogService


def _claims() -> AccessTokenClaims:
    return AccessTokenClaims(
        user_id=UUID("019f4220-5ce2-7082-b418-5d087d24a4a9"),
        session_id=UUID("019f4220-5ce2-7082-b418-5d087d24a4aa"),
    )


def test_seed_catalog_has_required_verified_content_and_retrieval_limits() -> None:
    engine = sa.create_engine("sqlite+pysqlite://")
    Base.metadata.create_all(engine)
    with Session(engine) as session:
        service = KnowledgeCatalogService(session)
        service.ensure_seeded()
        catalog = service.catalog()
        result = service.retrieve(
            goal="fat_loss",
            primary_sport="general_fitness",
            population_template_id="low_impact_fat_loss",
            equipment_access=("bodyweight", "dumbbell"),
        )

    assert catalog.version == "2026.08.02-v2"
    assert len(catalog.principles) == 15
    assert len(catalog.training_templates) == 9
    assert len(catalog.population_templates) == 8
    assert (
        sum(item.automatic_plan_allowed for item in catalog.population_templates)
        == 7
    )
    assert all(item.screening_extension_codes for item in catalog.population_templates)
    assert all(item.derived_constraint_codes for item in catalog.population_templates)
    assert all(item.session_structure_codes for item in catalog.population_templates)
    assert all(item.progression_rule_codes for item in catalog.population_templates)
    assert all(item.status == "verified" for item in catalog.principles)
    assert all(item.status == "verified" for item in catalog.training_templates)
    assert len(result.principles) <= 4
    assert len(result.training_templates) == 1
    assert result.training_templates[0].population_template_id == (
        "low_impact_fat_loss"
    )
    Base.metadata.drop_all(engine)
    engine.dispose()


def test_seed_catalog_updates_existing_reviewed_records_idempotently() -> None:
    engine = sa.create_engine("sqlite+pysqlite://")
    Base.metadata.create_all(engine)
    with Session(engine) as session:
        service = KnowledgeCatalogService(session)
        service.ensure_seeded()
        record = session.get(KnowledgePrincipleRecord, "periodization")
        assert record is not None
        record.title = "过期标题"
        record.content_version = "legacy"
        session.commit()

        service.ensure_seeded()
        restored = session.get(KnowledgePrincipleRecord, "periodization")

        assert restored is not None
        assert restored.title == "周期化"
        assert restored.content_version == "2026.08.02-v2"
    Base.metadata.drop_all(engine)
    engine.dispose()


def test_knowledge_catalog_endpoint_requires_login_and_has_no_raw_text() -> None:
    engine = sa.create_engine(
        "sqlite+pysqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(engine)
    session_factory = sessionmaker(bind=engine)
    app = create_app()

    def test_session() -> Generator[Session, None, None]:
        with session_factory() as session:
            yield session

    app.dependency_overrides[get_session] = test_session
    with TestClient(app) as unauthenticated:
        assert unauthenticated.get("/v1/knowledge/catalog").status_code == 401

    app.dependency_overrides[get_current_access_claims] = _claims
    with TestClient(app) as authenticated:
        response = authenticated.get("/v1/knowledge/catalog")

    assert response.status_code == 200
    body = response.json()
    assert len(body["principles"]) == 15
    assert len(body["training_templates"]) == 9
    assert len(body["population_templates"]) == 8
    serialized = response.text.lower()
    assert "raw_quote" not in serialized
    assert "book_text" not in serialized
    app.dependency_overrides.clear()
    Base.metadata.drop_all(engine)
    engine.dispose()
