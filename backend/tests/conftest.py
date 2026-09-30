"""pytest 共享夹具。

原则：测试**不碰**真实的 backend/anzhi.db。
每个测试用一个临时文件库，且使用与线上完全相同的引擎配置
（`create_db_engine` 会一并挂上 SQLite 外键 PRAGMA），
这样测试验证的行为和线上一致。
"""

from __future__ import annotations

from collections.abc import Generator

import pytest
from fastapi.testclient import TestClient
from sqlalchemy.engine import Engine
from sqlalchemy.orm import Session, sessionmaker

import app.models  # noqa: F401  —— 让 Base.metadata 拿到全部表定义
from app.database.base import Base
from app.database.session import create_db_engine, get_db
from app.main import app


@pytest.fixture
def test_engine(tmp_path) -> Generator[Engine, None, None]:
    """一个建好表、用完即弃的临时数据库引擎。"""
    engine = create_db_engine(f"sqlite:///{(tmp_path / 'test.db').as_posix()}")
    Base.metadata.create_all(bind=engine)
    yield engine
    engine.dispose()


@pytest.fixture
def db_session(test_engine: Engine) -> Generator[Session, None, None]:
    """临时数据库上的会话，供直接操作模型的测试使用。"""
    with Session(test_engine) as session:
        yield session


@pytest.fixture
def session_factory(test_engine: Engine) -> sessionmaker[Session]:
    """会话工厂，供接口测试在请求之外预置数据。"""
    return sessionmaker(bind=test_engine, autoflush=False, expire_on_commit=False)


@pytest.fixture
def api_client(session_factory: sessionmaker[Session]) -> Generator[TestClient, None, None]:
    """接入了临时数据库的 TestClient。

    通过覆盖 `get_db` 依赖把整个应用指向测试库 ——
    被测的仍是真实的 app，只有数据库被替换掉。
    """
    def _override_get_db() -> Generator[Session, None, None]:
        db = session_factory()
        try:
            yield db
        finally:
            db.close()

    app.dependency_overrides[get_db] = _override_get_db
    with TestClient(app) as client:
        yield client
    app.dependency_overrides.clear()
