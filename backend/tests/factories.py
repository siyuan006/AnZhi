"""测试数据工厂。

只负责**构造**对象，不负责 add / commit ——
事务时机由各测试自己掌控，这样「期望提交失败」的用例才好写。
"""

from __future__ import annotations

from sqlalchemy.orm import Session

from app.database.init_db import seed_categories
from app.models import Knowledge, User


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
