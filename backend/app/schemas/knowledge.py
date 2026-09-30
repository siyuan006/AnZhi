"""知识系统相关数据结构。对应 docs/API.md 第 4 节。"""

from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field

from app.models.knowledge import Knowledge


class CategoryOut(BaseModel):
    """分类（docs/API.md `GET /api/categories`）。"""

    model_config = ConfigDict(from_attributes=True)

    id: int
    name: str
    slug: str
    icon: str | None = None
    color: str | None = None
    description: str | None = None
    sort_order: int = 0


class KnowledgeListItem(BaseModel):
    """知识列表项。

    **不含 `content` 正文** —— 列表接口不返回正文，
    否则一页 20 条会把整篇正文全部拖下来。
    """

    id: int
    title: str
    category_id: int
    category_name: str = Field(..., description="分类显示名，分类缺失时为「未分类」")
    summary: str | None = None
    risk_level: str
    image_url: str | None = None
    created_at: datetime | None = None

    @classmethod
    def from_model(cls, item: Knowledge) -> "KnowledgeListItem":
        """从 ORM 对象构造。

        显式逐字段构造而不是 `from_attributes`：
        `category_name` 来自关联表，需要这一步映射，
        写清楚也比隐式规则更容易看懂。
        """
        return cls(
            id=item.id,
            title=item.title,
            category_id=item.category_id,
            category_name=item.category.name if item.category else "未分类",
            summary=item.summary,
            risk_level=item.risk_level,
            image_url=item.image_url,
            created_at=item.created_at,
        )


class KnowledgeDetail(KnowledgeListItem):
    """知识详情（docs/API.md `GET /api/knowledge/{id}`）。"""

    content: str
    source: str | None = None
    author: str | None = None
    view_count: int = 0

    @classmethod
    def from_model(cls, item: Knowledge) -> "KnowledgeDetail":
        return cls(
            id=item.id,
            title=item.title,
            category_id=item.category_id,
            category_name=item.category.name if item.category else "未分类",
            summary=item.summary,
            risk_level=item.risk_level,
            image_url=item.image_url,
            created_at=item.created_at,
            content=item.content,
            source=item.source,
            author=item.author,
            view_count=item.view_count,
        )
