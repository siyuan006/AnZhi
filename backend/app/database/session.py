"""数据库连接层：引擎、会话、请求级依赖。

对外提供三样东西：
    engine        全局引擎
    SessionLocal  会话工厂
    get_db()      FastAPI 依赖，每个请求一个会话

注意：本模块**不导入任何模型**，避免和 models 形成循环导入。
建表逻辑在 init_db.py 中。
"""

from __future__ import annotations

from collections.abc import Generator
from pathlib import Path

from sqlalchemy import create_engine, event
from sqlalchemy.engine import Engine
from sqlalchemy.orm import Session, sessionmaker

from app.config.settings import BACKEND_DIR, settings


def resolve_database_url(url: str) -> str:
    """把相对路径的 SQLite 地址固定到 backend/ 目录下。

    不做这一步的话，数据库文件会跟着「在哪个目录执行启动命令」跑：
    在 backend/ 下启动得到 backend/anzhi.db，
    在项目根目录启动得到 AnZhi/anzhi.db ——
    同一个项目凭空出现两个库，数据「消失」时非常难排查。
    """
    prefix = "sqlite:///"
    if not url.startswith(prefix):
        return url

    path_part = url[len(prefix) :]
    if path_part.startswith("./"):
        path_part = path_part[2:]

    candidate = Path(path_part)
    if candidate.is_absolute():
        return url

    return f"{prefix}{(BACKEND_DIR / candidate).as_posix()}"


def _set_sqlite_pragma(dbapi_connection, _connection_record) -> None:
    """SQLite 每个连接都要显式打开外键约束。

    SQLite 出于历史兼容，默认**不强制**外键。不打开的话，
    插入一条 category_id 根本不存在的知识卡片也会成功，外键形同虚设。
    """
    cursor = dbapi_connection.cursor()
    cursor.execute("PRAGMA foreign_keys=ON")
    cursor.close()


def create_db_engine(url: str) -> Engine:
    """按地址创建引擎，并做 SQLite 必需的适配。

    单独抽成函数是为了让测试能建一个「行为和线上完全一致」的临时库。
    """
    is_sqlite = url.startswith("sqlite")

    engine = create_engine(
        url,
        # SQLite 默认禁止跨线程复用连接，而 FastAPI 的同步依赖跑在线程池中
        connect_args={"check_same_thread": False} if is_sqlite else {},
    )

    if is_sqlite:
        event.listens_for(engine, "connect")(_set_sqlite_pragma)

    return engine


DATABASE_URL: str = resolve_database_url(settings.database_url)

engine: Engine = create_db_engine(DATABASE_URL)

SessionLocal = sessionmaker(
    bind=engine,
    autoflush=False,
    autocommit=False,
    # 提交后不过期对象，便于把 ORM 对象直接转成响应模型
    expire_on_commit=False,
)


def get_db() -> Generator[Session, None, None]:
    """FastAPI 依赖：每个请求一个会话，请求结束必定关闭。

    用法：
        @router.get("/api/xxx")
        def handler(db: Session = Depends(get_db)): ...
    """
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
