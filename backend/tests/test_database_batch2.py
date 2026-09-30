"""阶段 6-2：Favorite / History 两张表。

重点验证「规则真的落在数据库上」：
重复收藏、重复历史、指向不存在对象的记录，都应该被数据库拒绝，
而不是指望每处业务代码都记得先查一遍。
"""

from __future__ import annotations

import pytest
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.database.base import utcnow
from app.models import Favorite, History
from tests.factories import make_knowledge, make_user, prepare_categories


def _setup(db: Session) -> tuple[int, int]:
    """建好分类、一个用户、一篇知识，返回 (user_id, knowledge_id)。"""
    prepare_categories(db)

    user = make_user()
    knowledge = make_knowledge()
    db.add_all([user, knowledge])
    db.commit()

    return user.id, knowledge.id


class TestFavorite:
    """favorites 表。"""

    def test_can_favorite(self, db_session: Session) -> None:
        user_id, knowledge_id = _setup(db_session)

        db_session.add(Favorite(user_id=user_id, knowledge_id=knowledge_id))
        db_session.commit()

        favorite = db_session.scalars(select(Favorite)).one()
        assert favorite.user_id == user_id
        assert favorite.knowledge_id == knowledge_id
        assert favorite.created_at is not None

    def test_duplicate_favorite_is_rejected(self, db_session: Session) -> None:
        """同一用户重复收藏同一篇知识，数据库直接拒绝。"""
        user_id, knowledge_id = _setup(db_session)

        db_session.add(Favorite(user_id=user_id, knowledge_id=knowledge_id))
        db_session.commit()

        db_session.add(Favorite(user_id=user_id, knowledge_id=knowledge_id))
        with pytest.raises(IntegrityError):
            db_session.commit()

    def test_different_users_can_favorite_the_same_knowledge(
        self, db_session: Session
    ) -> None:
        """唯一约束是 (user_id, knowledge_id) 组合，不能误伤其他用户。"""
        user_id, knowledge_id = _setup(db_session)
        other = make_user(username="second")
        db_session.add(other)
        db_session.commit()

        # 两个不同用户收藏同一篇知识，都必须成功
        db_session.add_all(
            [
                Favorite(user_id=user_id, knowledge_id=knowledge_id),
                Favorite(user_id=other.id, knowledge_id=knowledge_id),
            ]
        )
        db_session.commit()

        assert len(db_session.scalars(select(Favorite)).all()) == 2

    def test_favorite_requires_existing_user(self, db_session: Session) -> None:
        _, knowledge_id = _setup(db_session)

        db_session.add(Favorite(user_id=9999, knowledge_id=knowledge_id))
        with pytest.raises(IntegrityError):
            db_session.commit()

    def test_favorite_requires_existing_knowledge(self, db_session: Session) -> None:
        user_id, _ = _setup(db_session)

        db_session.add(Favorite(user_id=user_id, knowledge_id=9999))
        with pytest.raises(IntegrityError):
            db_session.commit()


class TestHistory:
    """histories 表。"""

    def test_first_view_creates_a_record(self, db_session: Session) -> None:
        user_id, knowledge_id = _setup(db_session)

        db_session.add(History(user_id=user_id, knowledge_id=knowledge_id))
        db_session.commit()

        assert len(db_session.scalars(select(History)).all()) == 1

    def test_duplicate_history_row_is_rejected(self, db_session: Session) -> None:
        """docs/DATABASE.md 3.5：重复浏览不新增记录。

        这里故意用「再插一条」的错误做法，确认数据库会拦住它 ——
        这条 UNIQUE 约束就是那条规则的执行者。
        """
        user_id, knowledge_id = _setup(db_session)

        db_session.add(History(user_id=user_id, knowledge_id=knowledge_id))
        db_session.commit()

        db_session.add(History(user_id=user_id, knowledge_id=knowledge_id))
        with pytest.raises(IntegrityError):
            db_session.commit()

    def test_upsert_keeps_one_row_and_refreshes_time(
        self, db_session: Session
    ) -> None:
        """按约定的用法（存在则更新）重复浏览，仍然只有一条记录。

        真正的 upsert 业务实现属于阶段 11（收藏 / 历史），
        这里只验证「数据库约束允许这种写法」。
        """
        user_id, knowledge_id = _setup(db_session)

        def record_view() -> None:
            existing = db_session.scalar(
                select(History).where(
                    History.user_id == user_id,
                    History.knowledge_id == knowledge_id,
                )
            )
            if existing is not None:
                existing.viewed_at = utcnow()
            else:
                db_session.add(
                    History(user_id=user_id, knowledge_id=knowledge_id)
                )
            db_session.commit()

        record_view()
        first_seen = db_session.scalars(select(History)).one().viewed_at

        # 把时间往前拨，模拟「过了一段时间又看了一次」
        row = db_session.scalars(select(History)).one()
        row.viewed_at = first_seen.replace(year=2000)
        db_session.commit()

        record_view()

        rows = db_session.scalars(select(History)).all()
        assert len(rows) == 1
        assert rows[0].viewed_at.year != 2000

    def test_history_requires_existing_knowledge(self, db_session: Session) -> None:
        user_id, _ = _setup(db_session)

        db_session.add(History(user_id=user_id, knowledge_id=9999))
        with pytest.raises(IntegrityError):
            db_session.commit()

    def test_can_query_in_recent_order(self, db_session: Session) -> None:
        """历史列表按浏览时间倒序取数（索引 ix_histories_user_viewed 支撑）。"""
        user_id, first_knowledge_id = _setup(db_session)

        second = make_knowledge(title="插座冒烟怎么办")
        db_session.add(second)
        db_session.commit()

        older = utcnow().replace(year=2000)
        db_session.add_all(
            [
                History(
                    user_id=user_id,
                    knowledge_id=first_knowledge_id,
                    viewed_at=older,
                ),
                History(user_id=user_id, knowledge_id=second.id),
            ]
        )
        db_session.commit()

        ordered = db_session.scalars(
            select(History)
            .where(History.user_id == user_id)
            .order_by(History.viewed_at.desc())
        ).all()

        assert [row.knowledge_id for row in ordered] == [second.id, first_knowledge_id]
