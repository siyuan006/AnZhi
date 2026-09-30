"""测试数据工厂。

只负责**构造**对象，不负责 add / commit ——
事务时机由各测试自己掌控，这样「期望提交失败」的用例才好写。
"""

from __future__ import annotations

from sqlalchemy.orm import Session

from app.database.init_db import seed_categories
from app.models import Comment, Favorite, Knowledge, Post, User


def prepare_categories(db: Session) -> None:
    """写入六大分类并提交。

    需要合法 `category_id` 的测试都要先调用它 ——
    外键约束是真的生效的，不先建分类就插知识卡片会被拒绝。
    """
    seed_categories(db)
    db.commit()


def make_user(**overrides: object) -> User:
    """构造一个用户。"""
    payload: dict[str, object] = {
        "username": "tester",
        "password_hash": "hashed-password",
    }
    payload.update(overrides)
    return User(**payload)  # type: ignore[arg-type]


def make_knowledge(**overrides: object) -> Knowledge:
    """构造一篇知识卡片（默认 category_id=1，需先 prepare_categories）。"""
    payload: dict[str, object] = {
        "title": "灭火器的种类",
        "category_id": 1,
        "content": "常见的灭火器有干粉、二氧化碳、水基等……",
    }
    payload.update(overrides)
    return Knowledge(**payload)  # type: ignore[arg-type]


def make_post(**overrides: object) -> Post:
    """构造一个社区帖子。"""
    payload: dict[str, object] = {
        "user_id": 1,
        "title": "宿舍用电的几点提醒",
        "content": "不要在一个插排上同时接大功率电器……",
    }
    payload.update(overrides)
    return Post(**payload)  # type: ignore[arg-type]


def make_comment(**overrides: object) -> Comment:
    """构造一条评论。"""
    payload: dict[str, object] = {
        "post_id": 1,
        "user_id": 1,
        "content": "补充一点：充电器长期插着也会发热。",
    }
    payload.update(overrides)
    return Comment(**payload)  # type: ignore[arg-type]


def create_knowledge(db: Session, **overrides: object) -> Knowledge:
    """构造并**立即落库**一篇知识卡片，返回该对象。

    注意 `is_published` 默认是 False（PROJECT_SPEC 第十五节），
    想让它出现在对外接口里必须显式传 `is_published=True`。
    """
    item = make_knowledge(**overrides)
    db.add(item)
    db.commit()
    return item


def make_favorite(**overrides: object) -> Favorite:
    """构造一条收藏记录。"""
    payload: dict[str, object] = {"user_id": 1, "knowledge_id": 1}
    payload.update(overrides)
    return Favorite(**payload)  # type: ignore[arg-type]
