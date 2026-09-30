"""社区帖子相关数据结构。对应 docs/API.md 第 7 节。"""

from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, Field

from app.models.post import Post
from app.services.community.post_service import make_summary


class PostAuthor(BaseModel):
    """帖子作者。

    **只暴露 `name`，不暴露 `username`。**
    对社区来说只需要一个署名，而用户名是登录凭据的一半 ——
    公开它等于把每个发帖人的登录名挂在网上，配合撞库尝试很不划算。
    昵称优先，没设昵称时才退回用户名（那是用户自己填的展示名，
    与「登录名」是两件事，虽然没设昵称时取值相同）。
    """

    id: int = Field(..., description="作者用户 id")
    name: str = Field(..., description="署名：昵称优先，无昵称时为用户名")


class PostItem(BaseModel):
    """帖子列表的一行。**不含正文全文**，只有摘要。"""

    id: int
    title: str
    summary: str = Field(
        ..., description="正文摘要，由 content 截断而来，不是独立存储的字段"
    )
    category_id: int | None = None
    category_name: str | None = None
    author: PostAuthor
    like_count: int
    comment_count: int
    created_at: datetime

    @classmethod
    def from_model(cls, row: Post) -> "PostItem":
        """从 ORM 对象构造。

        调用方必须保证 `row.author` 与 `row.category` 已被加载
        （模型的 `lazy="joined"` 负责这件事）。
        """
        return cls(
            id=row.id,
            title=row.title,
            summary=make_summary(row.content),
            category_id=row.category_id,
            # 帖子可以不属于任何分类，此时 category 为 None
            category_name=row.category.name if row.category else None,
            author=PostAuthor(id=row.author.id, name=row.author_name),
            like_count=row.like_count,
            comment_count=row.comment_count,
            created_at=row.created_at,
        )


class PostDetail(BaseModel):
    """帖子详情。比列表项多一列完整的 `content`。"""

    id: int
    title: str
    content: str
    category_id: int | None = None
    category_name: str | None = None
    author: PostAuthor
    like_count: int
    comment_count: int
    created_at: datetime

    @classmethod
    def from_model(cls, row: Post) -> "PostDetail":
        return cls(
            id=row.id,
            title=row.title,
            content=row.content,
            category_id=row.category_id,
            category_name=row.category.name if row.category else None,
            author=PostAuthor(id=row.author.id, name=row.author_name),
            like_count=row.like_count,
            comment_count=row.comment_count,
            created_at=row.created_at,
        )
