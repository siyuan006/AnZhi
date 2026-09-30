"""pytest 共享夹具。

原则：测试**不碰**真实的 backend/anzhi.db。
每个测试用一个临时文件库，且使用与线上完全相同的引擎配置
（`create_db_engine` 会一并挂上 SQLite 外键 PRAGMA），
这样测试验证的行为和线上一致。
"""

from __future__ import annotations

from collections.abc import Generator
from pathlib import Path

import pytest
from sqlalchemy.orm import Session

import app.models  # noqa: F401  —— 让 Base.metadata 拿到全部表定义
from app.database.base import Base
from app.database.session import create_db_engine


@pytest.fixture
def db_session(tmp_path: Path) -> Generator[Session, None, None]:
    """一个建好表、用完即弃的临时数据库会话。"""
    engine = create_db_engine(f"sqlite:///{(tmp_path / 'test.db').as_posix()}")
    Base.metadata.create_all(bind=engine)

    with Session(engine) as session:
        yield session

    engine.dispose()
