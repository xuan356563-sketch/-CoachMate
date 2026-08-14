from sqlalchemy.orm import DeclarativeBase


class Base(DeclarativeBase):
    """后续领域模型共享的 SQLAlchemy 元数据基类。"""
