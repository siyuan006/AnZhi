"""知识卡片业务逻辑。

本层不感知 HTTP：不接收 Request、不抛 HTTPException，
只接收普通参数、返回 ORM 对象，因此可以脱离 Web 框架单独测试。
"""

from __future__ import annotations

from sqlalchemy import ColumnElement, Select, case, func, or_, select, update
from sqlalchemy.orm import Session

from app.models.category import Category
from app.models.knowledge import Knowledge

#: 列表与详情都只返回已发布内容。
#: 未发布内容属于「AI 初稿，尚未人工审核」，对外不可见
#: （PROJECT_SPEC 第十五节）。这个过滤条件不允许被调用方关掉。
_PUBLISHED_FILTER = Knowledge.is_published.is_(True)


def list_categories(db: Session) -> list[Category]:
    """按显示顺序返回全部分类。"""
    return list(
        db.scalars(
            select(Category).order_by(Category.sort_order, Category.id)
        ).all()
    )


def get_category(db: Session, category_id: int) -> Category | None:
    """按 id 取分类，不存在时返回 None。

    发帖要校验 `category_id` 是否真的存在：不校验的话外键约束会
    在 `commit()` 时抛 `IntegrityError`，用户看到的是一个 500，
    而不是「这个分类不存在」。分类查询集中在本模块，
    社区那边直接复用，不另写一份。
    """
    return db.get(Category, category_id)


def _filters(
    category_id: int | None,
    risk_level: str | None,
    keyword: str | None,
) -> list[ColumnElement[bool]]:
    """构造筛选条件。

    列表查询与计数查询**共用**这一份条件，否则很容易出现
    「总数说有 30 条、列表只返回 5 条」这种前后端对不上的问题。
    """
    conditions: list[ColumnElement[bool]] = [_PUBLISHED_FILTER]

    if category_id is not None:
        conditions.append(Knowledge.category_id == category_id)

    if risk_level is not None:
        conditions.append(Knowledge.risk_level == risk_level)

    if keyword:
        pattern = f"%{keyword.strip()}%"
        conditions.append(
            or_(Knowledge.title.like(pattern), Knowledge.summary.like(pattern))
        )

    return conditions


def _base_query(conditions: list[ColumnElement[bool]]) -> Select[tuple[Knowledge]]:
    return select(Knowledge).where(*conditions)


def count_knowledge(
    db: Session,
    *,
    category_id: int | None = None,
    risk_level: str | None = None,
    keyword: str | None = None,
) -> int:
    """符合条件的总条数。"""
    conditions = _filters(category_id, risk_level, keyword)
    total = db.scalar(select(func.count()).select_from(Knowledge).where(*conditions))
    return total or 0


def _preference_rank(
    prefer_category_ids: list[int],
) -> ColumnElement[int]:
    """把关注分类的内容排到前面。

    用 `CASE` 分两组（0 = 关注的、1 = 其余的），组内仍按发布时间倒序。
    没有写成「只查关注分类」：那会让用户在关注之后**看不到**其他内容，
    而关注的本意是调整先看到什么，不是把别的内容藏起来
    （PROJECT_SPEC 第十八节、四十二节）。
    """
    ids = sorted(set(prefer_category_ids))
    return case((Knowledge.category_id.in_(ids), 0), else_=1)


def list_knowledge(
    db: Session,
    *,
    category_id: int | None = None,
    risk_level: str | None = None,
    keyword: str | None = None,
    prefer_category_ids: list[int] | None = None,
    page: int = 1,
    page_size: int = 20,
) -> list[Knowledge]:
    """分页查询知识卡片，按发布时间倒序。

    排序里带上 `id` 作为第二关键字：同一天发布的多篇内容
    `created_at` 可能完全相同，只按时间排序时翻页会出现重复或漏项。

    `prefer_category_ids` 只改变**顺序**，不改变条数 ——
    因此 `count_knowledge` 里没有对应的参数。
    """
    conditions = _filters(category_id, risk_level, keyword)
    order_by: list[ColumnElement[object]] = []
    if prefer_category_ids:
        order_by.append(_preference_rank(prefer_category_ids))
    order_by.append(Knowledge.created_at.desc())
    order_by.append(Knowledge.id.desc())

    stmt = (
        _base_query(conditions)
        .order_by(*order_by)
        .offset((page - 1) * page_size)
        .limit(page_size)
    )
    return list(db.scalars(stmt).unique().all())


def get_knowledge(db: Session, knowledge_id: int) -> Knowledge | None:
    """按 id 取知识详情；不存在**或未发布**时返回 None。

    未发布内容对外一律视为「不存在」，不返回 403 ——
    否则等于告诉外部「这里有一篇还没审核的内容」。
    """
    return db.scalar(
        _base_query([_PUBLISHED_FILTER, Knowledge.id == knowledge_id])
    )


def increment_view_count(db: Session, knowledge_id: int) -> int | None:
    """把浏览量加一，返回新的浏览量；条目不存在或未发布时返回 None。

    刻意**不做成 `get_knowledge` 的副作用**，而是单独一个写接口：

    - GET 应当是幂等、可缓存的。带副作用的 GET 会被浏览器预取、
      爬虫、重试各加一次，统计出来的数字没有意义。
    - 「打开详情页」和「读取详情内容」是两件事。客户端明确地告诉服务端
      「用户真的看了这一条」，比服务端猜测要可靠。
    - 阶段 11 的浏览历史可以挂在同一个动作上，不需要再改一次接口。

    用 SQL 层的 `view_count = view_count + 1` 而不是「读出来 +1 再写回」：
    后者在并发下会丢更新（两个请求都读到 7，都写回 8）。
    """
    # 先确认对外的可见性，再自增。若直接 UPDATE 一个未发布的 id，
    # 会影响行数但用户看不到任何东西，等于把未发布内容的存在性泄露出去。
    if get_knowledge(db, knowledge_id) is None:
        return None

    db.execute(
        update(Knowledge)
        .where(Knowledge.id == knowledge_id)
        .values(view_count=Knowledge.view_count + 1)
    )
    db.commit()
    return db.scalar(select(Knowledge.view_count).where(Knowledge.id == knowledge_id))
