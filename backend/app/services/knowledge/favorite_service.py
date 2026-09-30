"""收藏业务逻辑。对应 docs/API.md 第 5 节与 PROJECT_SPEC 第三十九节。

分层（PROJECT_SPEC 第五十二节）：api → services → models，单向。
本模块不认识 HTTP：不接收 Request、不抛 HTTPException，
「这篇知识看不到」是业务结果，翻译成 404 是 api 层的事。

**幂等是这一层的核心约定**（docs/API.md 第 5 节要求「二选一」）：

    重复收藏 → 返回已有记录，不报错
    重复取消 → 视为成功

理由不是「少写点代码」，而是用户看到的那个按钮本来就是个开关。
他点「收藏」，想要的是「这条在我的收藏里」这个**状态**，
而不是「刚才那一瞬间成功插入了一行」。移动端还会自动重试、
用户会在网络慢的时候连点两下 —— 让这些情况弹出红色错误提示，
是在为一件已经达成的事情报错。
"""

from __future__ import annotations

from dataclasses import dataclass

from sqlalchemy import delete, func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.models.favorite import Favorite
from app.models.knowledge import Knowledge
from app.services.knowledge import knowledge_service

#: 未发布的知识对收藏同样不可见。
#: 用户收藏之后内容被撤下审核时，收藏列表里不能还留着一条点不开的入口。
_PUBLISHED_FILTER = Knowledge.is_published.is_(True)


@dataclass(frozen=True)
class FavoriteResult:
    """一次收藏操作的结果。

    - `favorite is None`：目标知识不存在或未发布
    - `created=False`：之前就收藏过，`favorite` 是那条已有记录

    用返回值而不是异常表达这两种情况，跟 `auth_service.AuthResult`
    是同一个理由：调用方每处都要 try，很容易漏掉一条分支而变成 500。
    """

    favorite: Favorite | None = None
    created: bool = False

    @property
    def ok(self) -> bool:
        return self.favorite is not None


def _find(db: Session, *, user_id: int, knowledge_id: int) -> Favorite | None:
    """取某个用户对某篇知识的收藏记录。

    `user_id` 是查询条件的一部分，不是可选的过滤条件 ——
    少了它，任何人都能读到别人的收藏。
    """
    return db.scalar(
        select(Favorite).where(
            Favorite.user_id == user_id,
            Favorite.knowledge_id == knowledge_id,
        )
    )


def add_favorite(db: Session, *, user_id: int, knowledge_id: int) -> FavoriteResult:
    """收藏一篇知识；已经收藏过则原样返回那条记录。"""
    # 先确认对外的可见性。直接给一个未发布的 id 建收藏，会让
    # 「这条内容存在吗」这个问题的答案从收藏接口漏出去。
    if knowledge_service.get_knowledge(db, knowledge_id) is None:
        return FavoriteResult()

    existing = _find(db, user_id=user_id, knowledge_id=knowledge_id)
    if existing is not None:
        return FavoriteResult(favorite=existing, created=False)

    favorite = Favorite(user_id=user_id, knowledge_id=knowledge_id)
    db.add(favorite)
    try:
        db.commit()
    except IntegrityError:
        # 上面刚查过一次，这里是并发兜底：两个请求同时点收藏时，
        # 只有数据库的 UNIQUE(user_id, knowledge_id) 靠得住。
        db.rollback()
        existing = _find(db, user_id=user_id, knowledge_id=knowledge_id)
        if existing is None:
            # 撞的不是「重复收藏」，而是知识在这两步之间被删掉/撤下了。
            # 对外同样按「看不到这条知识」处理，与上面的判断保持一致。
            return FavoriteResult()
        return FavoriteResult(favorite=existing, created=False)

    db.refresh(favorite)
    return FavoriteResult(favorite=favorite, created=True)


def remove_favorite(db: Session, *, user_id: int, knowledge_id: int) -> bool:
    """取消收藏，返回是否真的删掉了一行。

    **本来就没收藏也视为成功**：用户点「取消收藏」，想要的是
    「这条不在我的收藏里」，而这个状态已经成立了，没什么可报错的。
    返回值只用于测试和日志，接口层不据此改变状态码。

    `user_id` 必须在 WHERE 里：否则任何人都能靠猜 knowledge_id
    删掉别人的收藏。
    """
    result = db.execute(
        delete(Favorite).where(
            Favorite.user_id == user_id,
            Favorite.knowledge_id == knowledge_id,
        )
    )
    db.commit()
    return result.rowcount > 0


def is_favorited(db: Session, *, user_id: int | None, knowledge_id: int) -> bool:
    """这篇知识是否在该用户的收藏里；未登录时一律 False。

    只查主键，不取整行 —— 详情页每次打开都要问一次这个问题。
    """
    if user_id is None:
        return False
    return (
        db.scalar(
            select(Favorite.id).where(
                Favorite.user_id == user_id,
                Favorite.knowledge_id == knowledge_id,
            )
        )
        is not None
    )


def _visible_favorites(user_id: int):
    """收藏列表的基础查询：只保留**仍可见**的知识。

    INNER JOIN 而不是 LEFT JOIN：知识被撤下审核后，收藏记录还在数据库里，
    但它不该再出现在列表中 —— 列表里每一条都应该是点得开的。
    """
    return (
        select(Favorite)
        .join(Knowledge, Favorite.knowledge_id == Knowledge.id)
        .where(_PUBLISHED_FILTER, Favorite.user_id == user_id)
    )


def count_favorites(db: Session, *, user_id: int) -> int:
    """可见收藏的总条数。

    与 `list_favorites` 共用同一组条件，否则会出现
    「总数说有 10 条、列表只返回 7 条」这种对不上的分页。
    """
    total = db.scalar(
        select(func.count())
        .select_from(Favorite)
        .join(Knowledge, Favorite.knowledge_id == Knowledge.id)
        .where(_PUBLISHED_FILTER, Favorite.user_id == user_id)
    )
    return total or 0


def list_favorites(
    db: Session, *, user_id: int, page: int = 1, page_size: int = 20
) -> list[Favorite]:
    """分页返回收藏，按收藏时间倒序。

    排序里带 `id` 作第二关键字：同一秒内收藏的多条 `created_at`
    可能完全相同，只按时间排序时翻页会重复或漏项。
    """
    stmt = (
        _visible_favorites(user_id)
        .order_by(Favorite.created_at.desc(), Favorite.id.desc())
        .offset((page - 1) * page_size)
        .limit(page_size)
    )
    return list(db.scalars(stmt).unique().all())
