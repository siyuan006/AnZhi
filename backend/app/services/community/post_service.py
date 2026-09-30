"""社区帖子业务逻辑。

本层不感知 HTTP：不接收 Request、不抛 HTTPException，
只接收普通参数、返回 ORM 对象，因此可以脱离 Web 框架单独测试。
"""

from __future__ import annotations

import re

from sqlalchemy import ColumnElement, func, or_, select
from sqlalchemy.orm import Session

from app.models.post import Post

#: 列表与详情都只返回已发布的帖子。
#:
#: 注意 `posts.is_published` 与 `knowledge.is_published` 的默认值**不同**：
#: 知识默认 False（AI 初稿必须人工审核后才能发布，PROJECT_SPEC 第十五节），
#: 帖子默认 True（用户自己发的内容默认可见）。这里的过滤是为将来的
#: 「删帖 / 隐藏」预留的 —— 有过滤条件在，隐藏一条帖子不需要改接口。
_PUBLISHED_FILTER = Post.is_published.is_(True)

#: 列表里摘要的截断长度。
#:
#: 帖子表只有 `content`，没有独立的摘要字段（与 knowledge 不同），
#: 所以摘要由正文截断而来 —— 好处是它永远与正文一致，不可能对不上。
#: 取 120 个字：手机上一张卡片显示两行大约 40~50 字，留足冗余，
#: 将来界面想多显示一行也不必改后端。
SUMMARY_LENGTH = 120

_WHITESPACE = re.compile(r"\s+")


def make_summary(content: str) -> str:
    """把正文压成一行摘要。

    先折叠所有空白（换行、连续空格），再截断 —— 否则正文开头若是
    一段空行或缩进，摘要会以空白开头，在界面上看起来像没渲染出来。
    """
    collapsed = _WHITESPACE.sub(" ", content).strip()
    if len(collapsed) <= SUMMARY_LENGTH:
        return collapsed
    return collapsed[:SUMMARY_LENGTH] + "…"


def _filters(
    category_id: int | None,
    keyword: str | None,
) -> list[ColumnElement[bool]]:
    """构造筛选条件。

    列表查询与计数查询**共用**这一份条件，否则很容易出现
    「总数说有 30 条、列表只返回 5 条」这种前后端对不上的问题。
    """
    conditions: list[ColumnElement[bool]] = [_PUBLISHED_FILTER]

    if category_id is not None:
        conditions.append(Post.category_id == category_id)

    if keyword:
        pattern = f"%{keyword.strip()}%"
        conditions.append(
            or_(Post.title.like(pattern), Post.content.like(pattern))
        )

    return conditions


def count_posts(
    db: Session,
    *,
    category_id: int | None = None,
    keyword: str | None = None,
) -> int:
    """符合条件的帖子总数。"""
    conditions = _filters(category_id, keyword)
    total = db.scalar(select(func.count()).select_from(Post).where(*conditions))
    return total or 0


def list_posts(
    db: Session,
    *,
    category_id: int | None = None,
    keyword: str | None = None,
    page: int = 1,
    page_size: int = 20,
) -> list[Post]:
    """分页查询帖子，按发布时间倒序。

    排序里带上 `id` 作为第二关键字：同一秒发布的两条帖子
    `created_at` 可能完全相同，只按时间排序时翻页会出现重复或漏项。
    对社区来说这尤其容易发生 —— 帖子是用户随手发的，
    不像知识卡片那样有审核间隔。
    """
    conditions = _filters(category_id, keyword)
    stmt = (
        select(Post)
        .where(*conditions)
        .order_by(Post.created_at.desc(), Post.id.desc())
        .offset((page - 1) * page_size)
        .limit(page_size)
    )
    return list(db.scalars(stmt).unique().all())


def get_post(db: Session, post_id: int) -> Post | None:
    """按 id 取帖子；不存在或已隐藏时返回 None。

    已隐藏的帖子对外一律视为「不存在」（404 而非 403），
    与知识那边的处理一致。
    """
    return db.scalar(
        select(Post).where(_PUBLISHED_FILTER, Post.id == post_id)
    )
