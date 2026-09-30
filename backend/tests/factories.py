"""测试数据工厂。

只负责**构造**对象，不负责 add / commit ——
事务时机由各测试自己掌控，这样「期望提交失败」的用例才好写。
"""

from __future__ import annotations

from sqlalchemy.orm import Session

from app.database.init_db import seed_categories
from app.models import Comment, Favorite, History, Knowledge, Post, User


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


def create_user(db: Session, **overrides: object) -> User:
    """构造并**立即落库**一个用户，返回该对象。

    `username` 默认是 `tester`，要建多个用户时必须各自传不同的用户名 ——
    唯一约束是真的生效的。
    """
    user = make_user(**overrides)
    db.add(user)
    db.commit()
    return user


def create_post(db: Session, **overrides: object) -> Post:
    """构造并**立即落库**一个帖子，返回该对象。

    注意 `is_published` 默认是 **True**（与知识卡片相反，见 Post 模型的
    文档字符串）：用户自己发的帖子默认可见。想验证「隐藏的帖子不对外
    出现」必须显式传 `is_published=False`。

    帖子有指向 `users.id` 的外键，落库前要先有用户。
    """
    item = make_post(**overrides)
    db.add(item)
    db.commit()
    return item


def create_comment(db: Session, **overrides: object) -> Comment:
    """构造并**立即落库**一条评论，返回该对象。

    不会同步 `posts.comment_count` —— 那个计数由
    `comment_service.create_comment` 维护。直接用它造数据时
    想验计数，要自己把帖子的计数改对。
    """
    item = make_comment(**overrides)
    db.add(item)
    db.commit()
    return item


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


def make_history(**overrides: object) -> History:
    """构造一条浏览历史。

    `viewed_at` 不显式传入时由模型默认值（utcnow）填上。
    想验证排序的用例应当显式传时间，否则同一批记录的
    `viewed_at` 会撞在同一时刻，排序结果不可预期。
    """
    payload: dict[str, object] = {"user_id": 1, "knowledge_id": 1}
    payload.update(overrides)
    return History(**payload)  # type: ignore[arg-type]
