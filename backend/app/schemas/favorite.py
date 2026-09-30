"""收藏相关数据结构。对应 docs/API.md 第 5 节。"""

from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field

from app.models.favorite import Favorite
from app.schemas.knowledge import KnowledgeListItem


class FavoriteCreate(BaseModel):
    """`POST /api/favorites` 的请求体。"""

    knowledge_id: int = Field(..., ge=1, description="要收藏的知识 id")


class FavoriteOut(BaseModel):
    """`POST /api/favorites` 的响应（docs/API.md 第 5 节）。

    只回传收藏记录本身，不回传知识内容 —— 客户端是拿着 knowledge_id
    来收藏的，它手上已经有这条知识了，再传一遍纯属浪费。
    """

    model_config = ConfigDict(from_attributes=True)

    id: int
    knowledge_id: int
    created_at: datetime


class FavoriteItem(BaseModel):
    """收藏列表的一行。

    比 `FavoriteOut` 多带一份知识摘要：收藏列表要显示标题、分类和风险等级，
    只给 `knowledge_id` 的话客户端得为每一行再发一次详情请求（N+1）。
    """

    id: int
    knowledge_id: int
    created_at: datetime
    knowledge: KnowledgeListItem

    @classmethod
    def from_model(cls, favorite: Favorite) -> "FavoriteItem":
        """从 ORM 对象构造。

        调用方必须保证 `favorite.knowledge` 已被加载（模型的
        `lazy="joined"` 负责这件事），并且该知识是**已发布**的 ——
        列表查询已用 INNER JOIN 把未发布的排除掉了。
        """
        return cls(
            id=favorite.id,
            knowledge_id=favorite.knowledge_id,
            created_at=favorite.created_at,
            knowledge=KnowledgeListItem.from_model(favorite.knowledge),
        )
