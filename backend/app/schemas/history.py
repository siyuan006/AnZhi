"""浏览历史相关数据结构。对应 docs/API.md 第 6 节。"""

from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel

from app.models.history import History
from app.schemas.knowledge import KnowledgeListItem


class HistoryItem(BaseModel):
    """浏览历史列表的一行。

    比收藏多带一个 `viewed_at`，少一个 `id` 之外的包装 —— 结构与
    `FavoriteItem` 刻意保持一致（内嵌一份知识摘要），理由也一样：
    列表要显示标题、分类和风险等级，只给 `knowledge_id` 的话
    客户端得为每一行再发一次详情请求（N+1）。
    """

    id: int
    knowledge_id: int
    viewed_at: datetime
    knowledge: KnowledgeListItem

    @classmethod
    def from_model(cls, row: History) -> "HistoryItem":
        """从 ORM 对象构造。

        调用方必须保证 `row.knowledge` 已被加载（模型的 `lazy="joined"`
        负责这件事），并且该知识是**已发布**的 ——
        列表查询已用 INNER JOIN 把未发布的排除掉了。
        """
        return cls(
            id=row.id,
            knowledge_id=row.knowledge_id,
            viewed_at=row.viewed_at,
            knowledge=KnowledgeListItem.from_model(row.knowledge),
        )
