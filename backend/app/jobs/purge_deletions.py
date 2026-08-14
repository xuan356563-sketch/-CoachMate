from __future__ import annotations

from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.db.session import get_engine
from app.services.account_lifecycle import AccountLifecycleService


def run() -> int:
    """永久清理已超过撤销期的账号，并返回本次清理数量。"""
    with Session(get_engine()) as session:
        return AccountLifecycleService(
            session,
            get_settings(),
        ).purge_due_deletions()


def main() -> None:
    """命令行入口只输出聚合数量，不输出账号或删除请求标识。"""
    purged = run()
    print(f"已完成到期账号清理：{purged} 个")


if __name__ == "__main__":
    main()
