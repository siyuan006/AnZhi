"""阶段 6-1：数据库连接层与 User / Category / Knowledge 三张表。

这些测试验证的是**真实存在的约束行为**，不是「模型能实例化」这种空测试：
外键是否真的生效、唯一约束是否真的拦住重复、默认值是否真的是「不发布」。
"""

from __future__ import annotations

from datetime import datetime, timedelta
from pathlib import Path

import pytest
from sqlalchemy import select, text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.database.base import utcnow
from app.database.init_db import CATEGORY_SEEDS, seed_categories
from app.database.session import DATABASE_URL, resolve_database_url
from app.models import Category, Knowledge, User


def _make_knowledge(**overrides: object) -> Knowledge:
    """构造一张最小可用的知识卡片。"""
    payload: dict[str, object] = {
        "title": "灭火器的种类",
        "category_id": 1,
        "content": "常见的灭火器有干粉、二氧化碳、水基等……",
    }
    payload.update(overrides)
    return Knowledge(**payload)  # type: ignore[arg-type]


class TestDatabaseUrl:
    """数据库地址解析。"""

    def test_relative_sqlite_path_is_pinned_to_backend_dir(self) -> None:
        """相对路径必须固定到 backend/ 下，避免出现两个库文件。"""
        resolved = resolve_database_url("sqlite:///./anzhi.db")
        assert resolved.endswith("/backend/anzhi.db")
        assert resolved.startswith("sqlite:///")

    def test_absolute_sqlite_path_is_left_alone(self) -> None:
        absolute = "sqlite:///D:/tmp/other.db"
        assert resolve_database_url(absolute) == absolute

    def test_non_sqlite_url_is_left_alone(self) -> None:
        """将来换 PostgreSQL 时不应被这段逻辑改写。"""
        pg = "postgresql://user:pw@localhost:5432/anzhi"
        assert resolve_database_url(pg) == pg

    def test_configured_url_is_absolute_after_resolution(self) -> None:
        assert DATABASE_URL.startswith("sqlite:///")
        assert "backend/" in DATABASE_URL


class TestUserModel:
    """users 表。"""

    def test_defaults(self, db_session: Session) -> None:
        user = User(username="alice", password_hash="hashed-value")
        db_session.add(user)
        db_session.commit()

        assert user.id is not None
        assert user.study_days == 0
        assert user.email is None
        assert user.created_at is not None

    def test_username_must_be_unique(self, db_session: Session) -> None:
        db_session.add(User(username="bob", password_hash="h1"))
        db_session.commit()

        db_session.add(User(username="bob", password_hash="h2"))
        with pytest.raises(IntegrityError):
            db_session.commit()

    def test_email_must_be_unique_when_present(self, db_session: Session) -> None:
        db_session.add(User(username="u1", email="a@b.com", password_hash="h"))
        db_session.commit()

        db_session.add(User(username="u2", email="a@b.com", password_hash="h"))
        with pytest.raises(IntegrityError):
            db_session.commit()

    def test_repr_does_not_leak_password_hash(self, db_session: Session) -> None:
        """repr 会进日志，绝不能带出密码哈希（PROJECT_SPEC 第四十六节）。"""
        user = User(username="carol", password_hash="super-secret-hash")
        assert "super-secret-hash" not in repr(user)


class TestCategorySeeds:
    """六大分类种子数据。"""

    def test_seed_inserts_six_categories(self, db_session: Session) -> None:
        assert seed_categories(db_session) == 6
        db_session.commit()

        ids = sorted(db_session.scalars(select(Category.id)).all())
        assert ids == [1, 2, 3, 4, 5, 6]

    def test_seed_is_idempotent(self, db_session: Session) -> None:
        """重复执行不应产生重复分类（否则前端会出现两份同名分类）。"""
        seed_categories(db_session)
        db_session.commit()

        assert seed_categories(db_session) == 0
        db_session.commit()

        assert len(db_session.scalars(select(Category.id)).all()) == 6

    def test_slugs_are_unique(self) -> None:
        slugs = [seed.slug for seed in CATEGORY_SEEDS]
        assert len(slugs) == len(set(slugs))

    def test_ids_match_frontend_constants(self) -> None:
        """分类 id / slug 必须与前端 app_constants.dart 的 kCategories 一致。

        这里直接读取 Flutter 源文件来比对 —— 两边写死同一份数据，
        靠人眼保证同步迟早会漏，不如让测试直接比对文件内容。
        """
        constants = (
            Path(__file__).resolve().parents[2]
            / "frontend"
            / "lib"
            / "core"
            / "app_constants.dart"
        )
        if not constants.exists():  # 只 checkout 了 backend 时跳过
            pytest.skip("未找到前端常量文件")

        source = constants.read_text(encoding="utf-8")
        for seed in CATEGORY_SEEDS:
            assert f"id: {seed.id}," in source, f"前端缺少分类 id={seed.id}"
            assert f"slug: '{seed.slug}'" in source, f"前端缺少 slug={seed.slug}"
            assert f"name: '{seed.name}'" in source, f"前端分类名不一致：{seed.name}"


class TestKnowledgeModel:
    """knowledge 表。"""

    def test_is_published_defaults_to_false(self, db_session: Session) -> None:
        """默认不发布：未经人工审核的内容不得对外可见（PROJECT_SPEC 第十五节）。"""
        seed_categories(db_session)
        db_session.add(_make_knowledge())
        db_session.commit()

        assert db_session.scalars(select(Knowledge)).one().is_published is False

    def test_risk_level_defaults_to_low(self, db_session: Session) -> None:
        seed_categories(db_session)
        db_session.add(_make_knowledge())
        db_session.commit()
        assert db_session.scalars(select(Knowledge)).one().risk_level == "low"

    def test_foreign_key_to_missing_category_is_rejected(
        self, db_session: Session
    ) -> None:
        """SQLite 默认不强制外键，本测试确认 PRAGMA foreign_keys=ON 真的生效。"""
        db_session.add(_make_knowledge(category_id=999))
        with pytest.raises(IntegrityError):
            db_session.commit()

    def test_foreign_key_to_existing_category_is_accepted(
        self, db_session: Session
    ) -> None:
        seed_categories(db_session)
        db_session.commit()

        db_session.add(_make_knowledge(category_id=1))
        db_session.commit()

        assert db_session.scalars(select(Knowledge)).one().category_id == 1

    def test_invalid_risk_level_is_rejected(self, db_session: Session) -> None:
        """CHECK 约束挡住 'HIGH' / '高危' 这类脏数据。"""
        seed_categories(db_session)
        db_session.commit()

        db_session.add(_make_knowledge(risk_level="HIGH"))
        with pytest.raises(IntegrityError):
            db_session.commit()

    def test_content_is_required(self, db_session: Session) -> None:
        seed_categories(db_session)
        db_session.commit()

        db_session.add(Knowledge(title="无正文", category_id=1))
        with pytest.raises(IntegrityError):
            db_session.commit()


class TestTimestamps:
    """时间字段。"""

    def test_utcnow_is_naive_utc(self) -> None:
        """全项目统一 naive UTC，避免 aware / naive 比较报错。"""
        now = utcnow()
        assert now.tzinfo is None

    def test_updated_at_changes_on_update(self, db_session: Session) -> None:
        seed_categories(db_session)
        db_session.commit()

        item = _make_knowledge()
        db_session.add(item)
        db_session.commit()
        created_at = item.created_at

        # 把时间往前拨到一个 utcnow() 不可能产生的值（哨兵），
        # 这样才能区分「onupdate 真的重新写了时间」和「值恰好没变」。
        # 用字符串绑定而不是 datetime 对象：Python 3.12 起 sqlite3
        # 已移除 datetime 的隐式适配器，裸 SQL 里传 datetime 会告警甚至报错。
        sentinel = datetime(2000, 1, 1)
        db_session.execute(
            text("UPDATE knowledge SET updated_at = :value"),
            {"value": sentinel.strftime("%Y-%m-%d %H:%M:%S.%f")},
        )
        db_session.commit()
        db_session.refresh(item)
        assert item.updated_at == sentinel

        item.title = "改过的标题"
        db_session.commit()
        db_session.refresh(item)

        # 这里**不能**写成 `updated_at != 改动前的 updated_at`：
        # Windows 上 datetime.now() 的实际分辨率约为 1 毫秒
        # （实测连调两万次只返回 11 个不同值），
        # 插入与更新若落在同一个时钟刻度内，两次 utcnow() 连微秒都完全一样，
        # 断言会随机失败。改为断言「不再是哨兵值」+「接近当前时间」。
        assert item.updated_at != sentinel
        assert utcnow() - item.updated_at < timedelta(seconds=5)
        assert item.created_at == created_at
