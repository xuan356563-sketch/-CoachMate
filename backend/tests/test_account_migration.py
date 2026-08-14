from __future__ import annotations

import importlib.util
from datetime import timedelta
from pathlib import Path
from types import ModuleType
from uuid import uuid4

import sqlalchemy as sa
from alembic.migration import MigrationContext
from alembic.operations import Operations
from sqlalchemy import event, select
from sqlalchemy.orm import Session

from app.core.config import Settings
from app.core.security import utc_now
from app.db.base import Base
from app.models import (
    AccountDeletionReceipt,
    AccountDeletionRequest,
    TrainingPreference,
    User,
)
from app.services.account_lifecycle import AccountLifecycleService

MIGRATION_PATH = (
    Path(__file__).parents[1]
    / "alembic"
    / "versions"
    / "20260728_0006_account_lifecycle.py"
)


def _load_migration() -> ModuleType:
    spec = importlib.util.spec_from_file_location(
        "account_lifecycle_migration",
        MIGRATION_PATH,
    )
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_account_lifecycle_migration_keeps_receipt_anonymous() -> None:
    """匿名回执若含 user_id 或登录标识列，会破坏永久删除边界。"""
    engine = sa.create_engine("sqlite+pysqlite://")
    metadata = sa.MetaData()
    sa.Table("users", metadata, sa.Column("id", sa.Uuid(), primary_key=True))
    metadata.create_all(engine)

    with engine.begin() as connection:
        migration = _load_migration()
        migration.op = Operations(MigrationContext.configure(connection))
        migration.upgrade()
        inspector = sa.inspect(connection)
        assert {
            "account_export_records",
            "account_deletion_challenges",
            "account_deletion_requests",
            "account_deletion_receipts",
        }.issubset(set(inspector.get_table_names()))
        receipt_columns = {
            column["name"]
            for column in inspector.get_columns("account_deletion_receipts")
        }
        assert receipt_columns == {
            "id",
            "deletion_request_id",
            "completed_at",
        }
        assert migration.down_revision == "20260728_0005"

    engine.dispose()


def test_due_deletion_purges_identity_and_business_rows_but_keeps_receipt() -> None:
    """只更新任务状态而未删除用户投影时，此测试必须失败。"""
    engine = sa.create_engine("sqlite+pysqlite://")

    @event.listens_for(engine, "connect")
    def _enable_foreign_keys(dbapi_connection, _connection_record) -> None:
        cursor = dbapi_connection.cursor()
        cursor.execute("PRAGMA foreign_keys=ON")
        cursor.close()

    Base.metadata.create_all(engine)
    user_id = uuid4()
    request_id = uuid4()
    with Session(engine) as session:
        session.add(
            User(
                id=user_id,
                email_hash="摘要",
                masked_email="d***@example.com",
            ),
        )
        session.commit()
        session.add(
            TrainingPreference(
                id=uuid4(),
                user_id=user_id,
                version=1,
                goal="测试",
                sport_types=["running"],
                experience_level="beginner",
                weekly_availability=[2],
                equipment=[],
            ),
        )
        session.add(
            AccountDeletionRequest(
                id=request_id,
                user_id=user_id,
                status="pending",
                requested_at=utc_now() - timedelta(days=8),
                purge_after=utc_now() - timedelta(days=1),
            ),
        )
        session.commit()

        purged = AccountLifecycleService(
            session,
            Settings(sync_enabled=True),
        ).purge_due_deletions()

        assert purged == 1
        assert session.get(User, user_id) is None
        assert session.scalar(
            select(TrainingPreference).where(
                TrainingPreference.user_id == user_id,
            ),
        ) is None
        assert session.get(AccountDeletionRequest, request_id) is None
        receipt = session.scalar(select(AccountDeletionReceipt))
        assert receipt is not None
        assert receipt.deletion_request_id == request_id

    Base.metadata.drop_all(engine)
    engine.dispose()
