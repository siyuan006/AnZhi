"""浏览历史业务逻辑。对应 docs/API.md 第 6 节、docs/DATABASE.md 3.5。

分层规则同 knowledge_service / favorite_service：
`api → services → models` 单向，本模块**不认识 HTTP** ——
不接收 Request、不抛 HTTPException，「这篇看不到」是业务结果，
翻译成 404 是 api 层的事。

**核心约定：同一用户重复浏览同一篇知识，只更新时间，不新增记录。**

这不是「顺手做的去重」，而是 docs/DATABASE.md 3.5 明文规定的行为，
并且已经由表上的 `UNIQUE(user_id, knowledge_id)` 固化到数据库层 ——
业务层即使漏判，数据库也不会产生重复行。之所以两边都做，
是因为只有数据库约束能保证并发下的正确性，而只有业务层的
「存在则更新」才能把时间刷新成最近一次浏览的时刻。
"""

from __future__ import annotations

from sqlalchemy import ColumnElement, Select, delete, func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.database.base import utcnow
from app.models.history import History
from app.models.knowledge import Knowledge
from app.services.knowledge import knowledge_service

#: 与知识列表、收藏列表保持一致：未发布内容一律视为不存在
#: （PROJECT_SPEC 第十五节）。这个过滤条件不允许被调用方关掉。
_PUBLISHED_FILTER = Knowledge.is_published.is_(True)


def _find(db: Session, *, user_id: int, knowledge_id: int) -> History | None:
    """取某个用户对某篇知识的那一条历史记录。"""
    return db.scalar(
        select(History).where(
            History.user_id == user_id,
            History.knowledge_id == knowledge_id,
        )
    )


def record_view(db: Session, *, user_id: int, knowledge_id: int) -> bool:
    """记录一次浏览，返回是否记上了。

    存在则把 `viewed_at` 刷新为当前时间，不存在才插入新行。

    条目不存在或未发布时返回 `False` 且不写任何东西 ——
    与 `increment_view_count` 的理由相同：给一个未发布的 id 写历史，
    等于通过「有没有记录」对外确认了这条内容存在。
    """
    if knowledge_service.get_knowledge(db, knowledge_id) is None:
        return False

    existing = _find(db, user_id=user_id, knowledge_id=knowledge_id)
    if existing is not None:
        # 走更新分支：不新增行，只把时间推到这一次
        existing.viewed_at = utcnow()
        db.commit()
        return True

    db.add(History(user_id=user_id, knowledge_id=knowledge_id))
    try:
        db.commit()
    except IntegrityError:
        # 并发下另一个请求抢先插入了同一对 (user_id, knowledge_id)。
        # UNIQUE 约束挡住了重复行，这里退化成「更新那一条」，
        # 而不是把一次正常的浏览变成错误。
        db.rollback()
        existing = _find(db, user_id=user_id, knowledge_id=knowledge_id)
        if existing is None:
            return False
        existing.viewed_at = utcnow()
        db.commit()
        return True

    return True


def _visible_conditions(user_id: int) -> list[ColumnElement[bool]]:
    """某个用户「可见的历史」的筛选条件。

    列表与计数**共用这一份**，否则会出现「总数说有 10 条、
    列表只返回 7 条」这种前后端对不上的问题。
    """
    return [_PUBLISHED_FILTER, History.user_id == user_id]


def _joined(user_id: int) -> Select[tuple[History]]:
    """可见历史的基础查询。

    用 INNER JOIN 连上 Knowledge 并过滤未发布内容：用户浏览过、
    但后来被撤回的内容不该继续留在列表里。
    """
    return (
        select(History)
        .join(Knowledge, History.knowledge_id == Knowledge.id)
        .where(*_visible_conditions(user_id))
    )


def count_history(db: Session, *, user_id: int) -> int:
    """可见的历史条数。"""
    total = db.scalar(
        select(func.count())
        .select_from(History)
        .join(Knowledge, History.knowledge_id == Knowledge.id)
        .where(*_visible_conditions(user_id))
    )
    return total or 0


def list_history(
    db: Session,
    *,
    user_id: int,
    page: int = 1,
    page_size: int = 20,
) -> list[History]:
    """分页查询浏览历史，按最近浏览倒序（docs/API.md 第 6 节）。

    排序带上 `id` 作为第二关键字：`viewed_at` 的精度有限，
    连续浏览多条时可能撞在同一时刻，只按时间排序翻页会出现重复或漏项。
    """
    stmt = (
        _joined(user_id)
        .order_by(History.viewed_at.desc(), History.id.desc())
        .offset((page - 1) * page_size)
        .limit(page_size)
    )
    return list(db.scalars(stmt).unique().all())


def remove_one(db: Session, *, user_id: int, knowledge_id: int) -> bool:
    """删除单条历史，返回是否真的删掉了一行。

    条件里必须带 `user_id`：只按 `knowledge_id` 删会把别人的历史一起删掉。
    返回的布尔值只作参考 —— api 层对「没删到」同样返回 204，
    理由见 `favorite_service.remove_favorite`：用户要的是「这条不在我的
    历史里」，而这个状态已经成立了。
    """
    result = db.execute(
        delete(History).where(
            History.user_id == user_id,
            History.knowledge_id == knowledge_id,
        )
    )
    db.commit()
    return result.rowcount > 0


def clear_all(db: Session, *, user_id: int) -> int:
    """清空某个用户的全部历史，返回删除条数。

    同样必须带 `user_id` —— 这是本模块里破坏性最强的一个操作，
    漏掉这个条件就是清空了所有人的历史。
    """
    result = db.execute(delete(History).where(History.user_id == user_id))
    db.commit()
    return result.rowcount
