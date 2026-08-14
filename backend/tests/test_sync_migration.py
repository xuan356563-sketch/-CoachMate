from __future__ import annotations

import importlib.util
from pathlib import Path
from types import ModuleType

import sqlalchemy as sa
from alembic.migration import MigrationContext
from alembic.operations import Operations

MIGRATION_PATH = (
    Path(__file__).parents[1]
    / "alembic"
    / "versions"
    / "20260728_0005_cloud_sync.py"
)


def _load_migration() -> ModuleType:
    spec = importlib.util.spec_from_file_location(
        "cloud_sync_migration",
        MIGRATION_PATH,
    )
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_cloud_sync_migration_creates_only_whitelisted_projection_columns() -> None:
    """加入敏感字段或漏建幂等/游标表时应阻止迁移进入交付。"""
    engine = sa.create_engine("sqlite+pysqlite://")
    metadata = sa.MetaData()
    sa.Table("users", metadata, sa.Column("id", sa.Uuid(), primary_key=True))
    metadata.create_all(engine)

    with engine.begin() as connection:
        migration = _load_migration()
        migration.op = Operations(MigrationContext.configure(connection))
        migration.upgrade()

        inspector = sa.inspect(connection)
        expected_tables = {
            "training_preferences",
            "cloud_plan_versions",
            "cloud_scheduled_workouts",
            "completion_summaries",
            "user_app_settings",
            "sync_mutations",
            "sync_changes",
        }
        assert expected_tables.issubset(set(inspector.get_table_names()))

        banned_fragments = {
            "name",
            "age",
            "sex",
            "gender",
            "height",
            "weight",
            "occupation",
            "healthkit",
            "pain",
            "rpe",
            "note",
            "heart_rate",
            "route",
            "image",
            "audio",
            "voice",
        }
        projection_tables = expected_tables - {"sync_mutations", "sync_changes"}
        projection_columns = {
            column["name"]
            for table in projection_tables
            for column in inspector.get_columns(table)
        }
        assert projection_columns.isdisjoint(banned_fragments)
        assert migration.down_revision == "20260716_0004"

    engine.dispose()
