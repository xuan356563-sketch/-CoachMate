from __future__ import annotations

import importlib.util
from pathlib import Path
from types import ModuleType

import sqlalchemy as sa
from alembic.migration import MigrationContext
from alembic.operations import Operations

VERSIONS = Path(__file__).parents[1] / "alembic" / "versions"


def _load(name: str) -> ModuleType:
    path = VERSIONS / name
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_profile_and_billing_migrations_upgrade_and_rollback() -> None:
    engine = sa.create_engine("sqlite+pysqlite://")
    metadata = sa.MetaData()
    sa.Table("users", metadata, sa.Column("id", sa.Uuid(), primary_key=True))
    metadata.create_all(engine)

    with engine.begin() as connection:
        profile = _load("20260731_0010_cloud_user_profile.py")
        billing = _load("20260731_0011_subscription_billing.py")
        operations = Operations(MigrationContext.configure(connection))
        profile.op = operations
        billing.op = operations

        profile.upgrade()
        billing.upgrade()
        inspector = sa.inspect(connection)
        assert {
            "cloud_user_profiles",
            "subscription_entitlements",
            "apple_subscription_events",
        }.issubset(inspector.get_table_names())
        profile_columns = {
            item["name"] for item in inspector.get_columns("cloud_user_profiles")
        }
        assert "ciphertext" in profile_columns
        assert "nickname" not in profile_columns
        assert "height_cm" not in profile_columns

        billing.downgrade()
        profile.downgrade()
        assert "cloud_user_profiles" not in sa.inspect(connection).get_table_names()

    engine.dispose()
