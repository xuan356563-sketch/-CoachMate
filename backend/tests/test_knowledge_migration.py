from __future__ import annotations

import importlib.util
from pathlib import Path
from types import ModuleType

import sqlalchemy as sa
from alembic.migration import MigrationContext
from alembic.operations import Operations
from sqlalchemy import inspect

VERSIONS = Path(__file__).parents[1] / "alembic" / "versions"


def _load_migration(filename: str) -> ModuleType:
    path = VERSIONS / filename
    spec = importlib.util.spec_from_file_location(path.stem, path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_knowledge_catalog_migration_upgrades_and_rolls_back() -> None:
    engine = sa.create_engine("sqlite+pysqlite://")
    migration = _load_migration("20260730_0009_knowledge_catalog.py")
    with engine.begin() as connection:
        migration.op = Operations(MigrationContext.configure(connection))
        migration.upgrade()
        upgraded_tables = set(inspect(connection).get_table_names())
        principle_columns = {
            item["name"]
            for item in inspect(connection).get_columns("knowledge_principles")
        }
        migration.downgrade()
        rolled_back_tables = set(inspect(connection).get_table_names())

    assert migration.down_revision == "20260730_0008"
    assert {"knowledge_principles", "training_templates"} <= upgraded_tables
    assert {"status", "summary", "content_version"} <= principle_columns
    assert "knowledge_principles" not in rolled_back_tables
    assert "training_templates" not in rolled_back_tables
    engine.dispose()
