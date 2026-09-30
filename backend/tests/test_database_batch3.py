"""阶段 6-3：Post / Comment / Like / UserSettings 四张表。

这批表是阶段 6 的最后一批，建完后数据库结构与 docs/DATABASE.md 完全对齐。
"""

from __future__ import annotations

import pytest
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.models import Comment, Like, Post, UserSettings
from tests.factories import make_comment, make_post, make_user


def _make_users(db: Session, *usernames: str) -> dict[str, int]:
    """建若干个用户，返回 {用户名: id}。"""
    users = {name: make_user(username=name) for name in usernames}
    db.add_all(list(users.values()))
    db.commit()
    return {name: user.id for name, user in users.items()}


class TestPost:
    """posts 表。"""

    def test_defaults(self, db_session: Session) -> None:
        user_id = _make_users(db_session, "author")["author"]

        post = make_post(user_id=user_id)
        db_session.add(post)
        db_session.commit()

        assert post.id is not None
        assert post.like_count == 0
        assert post.comment_count == 0
        assert post.category_id is None

    def test_is_published_defaults_to_true(self, db_session: Session) -> None:
        """用户自己发的帖子默认可见 —— 与知识卡片默认不发布是刻意相反的。"""
        user_id = _make_users(db_session, "author")["author"]

        db_session.add(make_post(user_id=user_id))
        db_session.commit()

        assert db_session.scalars(select(Post)).one().is_published is True

    def test_requires_existing_user(self, db_session: Session) -> None:
        db_session.add(make_post(user_id=9999))
        with pytest.raises(IntegrityError):
            db_session.commit()

    def test_content_is_required(self, db_session: Session) -> None:
        user_id = _make_users(db_session, "author")["author"]

        db_session.add(Post(user_id=user_id, title="只有标题"))
        with pytest.raises(IntegrityError):
            db_session.commit()

    def test_negative_like_count_is_rejected(self, db_session: Session) -> None:
        """计数不允许为负：CHECK 约束挡住明显错误的写入。"""
        user_id = _make_users(db_session, "author")["author"]

        db_session.add(make_post(user_id=user_id, like_count=-1))
        with pytest.raises(IntegrityError):
            db_session.commit()


class TestComment:
    """comments 表。"""

    def test_can_comment(self, db_session: Session) -> None:
        ids = _make_users(db_session, "author", "reader")
        post = make_post(user_id=ids["author"])
        db_session.add(post)
        db_session.commit()

        db_session.add(make_comment(post_id=post.id, user_id=ids["reader"]))
        db_session.commit()

        comment = db_session.scalars(select(Comment)).one()
        assert comment.post_id == post.id
        assert comment.parent_id is None

    def test_requires_existing_post(self, db_session: Session) -> None:
        ids = _make_users(db_session, "reader")

        db_session.add(make_comment(post_id=9999, user_id=ids["reader"]))
        with pytest.raises(IntegrityError):
            db_session.commit()

    def test_reply_to_comment_is_supported(self, db_session: Session) -> None:
        """parent_id 自引用外键可用，为二级回复预留。"""
        ids = _make_users(db_session, "author", "reader")
        post = make_post(user_id=ids["author"])
        db_session.add(post)
        db_session.commit()

        parent = make_comment(post_id=post.id, user_id=ids["reader"])
        db_session.add(parent)
        db_session.commit()

        reply = make_comment(
            post_id=post.id,
            user_id=ids["author"],
            content="你说得对。",
            parent_id=parent.id,
        )
        db_session.add(reply)
        db_session.commit()

        assert reply.parent_id == parent.id

    def test_parent_must_exist(self, db_session: Session) -> None:
        ids = _make_users(db_session, "author", "reader")
        post = make_post(user_id=ids["author"])
        db_session.add(post)
        db_session.commit()

        db_session.add(
            make_comment(post_id=post.id, user_id=ids["reader"], parent_id=9999)
        )
        with pytest.raises(IntegrityError):
            db_session.commit()


class TestLike:
    """likes 表。"""

    def test_can_like(self, db_session: Session) -> None:
        ids = _make_users(db_session, "author", "reader")
        post = make_post(user_id=ids["author"])
        db_session.add(post)
        db_session.commit()

        db_session.add(Like(post_id=post.id, user_id=ids["reader"]))
        db_session.commit()

        assert len(db_session.scalars(select(Like)).all()) == 1

    def test_duplicate_like_is_rejected(self, db_session: Session) -> None:
        """同一用户对同一帖子只能点赞一次。"""
        ids = _make_users(db_session, "author", "reader")
        post = make_post(user_id=ids["author"])
        db_session.add(post)
        db_session.commit()

        db_session.add(Like(post_id=post.id, user_id=ids["reader"]))
        db_session.commit()

        db_session.add(Like(post_id=post.id, user_id=ids["reader"]))
        with pytest.raises(IntegrityError):
            db_session.commit()

    def test_different_users_can_like_the_same_post(self, db_session: Session) -> None:
        ids = _make_users(db_session, "author", "reader1", "reader2")
        post = make_post(user_id=ids["author"])
        db_session.add(post)
        db_session.commit()

        db_session.add_all(
            [
                Like(post_id=post.id, user_id=ids["reader1"]),
                Like(post_id=post.id, user_id=ids["reader2"]),
            ]
        )
        db_session.commit()

        assert len(db_session.scalars(select(Like)).all()) == 2

    def test_requires_existing_post(self, db_session: Session) -> None:
        ids = _make_users(db_session, "reader")

        db_session.add(Like(post_id=9999, user_id=ids["reader"]))
        with pytest.raises(IntegrityError):
            db_session.commit()


class TestUserSettings:
    """user_settings 表。"""

    def test_defaults(self, db_session: Session) -> None:
        user_id = _make_users(db_session, "alice")["alice"]

        db_session.add(UserSettings(user_id=user_id))
        db_session.commit()

        settings = db_session.scalars(select(UserSettings)).one()
        assert settings.followed_categories == []
        assert settings.home_modules == []
        assert settings.notify_enabled is True

    def test_one_settings_row_per_user(self, db_session: Session) -> None:
        """与用户一对一，第二条会被拒绝。"""
        user_id = _make_users(db_session, "alice")["alice"]

        db_session.add(UserSettings(user_id=user_id))
        db_session.commit()

        db_session.add(UserSettings(user_id=user_id))
        with pytest.raises(IntegrityError):
            db_session.commit()

    def test_json_values_round_trip(self, db_session: Session) -> None:
        user_id = _make_users(db_session, "alice")["alice"]

        db_session.add(
            UserSettings(user_id=user_id, followed_categories=[1, 5])
        )
        db_session.commit()
        db_session.expire_all()

        settings = db_session.scalars(select(UserSettings)).one()
        assert settings.followed_categories == [1, 5]

    def test_in_place_list_mutation_is_persisted(self, db_session: Session) -> None:
        """就地 append 必须被写进数据库。

        这是 MutableList 存在的唯一理由：不套它的话，
        `settings.followed_categories.append(1)` 不会报错、也不会保存，
        属于「代码看起来对、数据就是没存上」的隐形 bug。
        """
        user_id = _make_users(db_session, "alice")["alice"]

        settings = UserSettings(user_id=user_id)
        db_session.add(settings)
        db_session.commit()

        settings.followed_categories.append(3)
        db_session.commit()
        db_session.expire_all()

        reloaded = db_session.scalars(select(UserSettings)).one()
        assert reloaded.followed_categories == [3]

    def test_each_user_has_independent_settings(self, db_session: Session) -> None:
        ids = _make_users(db_session, "alice", "bob")

        db_session.add_all(
            [
                UserSettings(user_id=ids["alice"], followed_categories=[1]),
                UserSettings(user_id=ids["bob"], followed_categories=[2]),
            ]
        )
        db_session.commit()

        rows = {
            row.user_id: row.followed_categories
            for row in db_session.scalars(select(UserSettings)).all()
        }
        assert rows == {ids["alice"]: [1], ids["bob"]: [2]}
