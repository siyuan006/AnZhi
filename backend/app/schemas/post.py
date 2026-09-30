"""社区帖子相关数据结构。对应 docs/API.md 第 7 节。"""

from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, Field, field_validator

from app.models.post import Post
from app.services.community import post_service
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
    is_liked: bool = False

    @classmethod
    def from_model(cls, row: Post, *, is_liked: bool = False) -> "PostItem":
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
            is_liked=is_liked,
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
    is_liked: bool = False

    @classmethod
    def from_model(cls, row: Post, *, is_liked: bool = False) -> "PostDetail":
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
            is_liked=is_liked,
        )


class PostCreate(BaseModel):
    """发布帖子的请求体。

    **长度校验写在 `field_validator` 里，不写成 `Field(max_length=…)`。**
    后者作用在**原始值**上，而且在 validator **之前**执行：
    `"  " + 200 个字 + `"  "` 会被判超长，而用户看到的明明没超。
    统一在 validator 里对规范化之后的文本判，才不会出现
    「校验的和入库的不是同一个东西」（阶段 12b 的评论区踩过这个坑）。
    """

    title: str = Field(..., description="标题，会被压成单行")
    content: str = Field(..., description="正文，保留分段")
    category_id: int | None = Field(None, ge=1, description="分类，可不填")

    @field_validator("title")
    @classmethod
    def check_title(cls, value: str) -> str:
        normalized = post_service.normalize_title(value)
        if len(normalized) < post_service.TITLE_MIN_LENGTH:
            raise ValueError("标题不能为空")
        if len(normalized) > post_service.TITLE_MAX_LENGTH:
            raise ValueError(f"标题最长 {post_service.TITLE_MAX_LENGTH} 个字")
        return normalized

    @field_validator("content")
    @classmethod
    def check_content(cls, value: str) -> str:
        normalized = post_service.normalize_content(value)
        if len(normalized) < post_service.CONTENT_MIN_LENGTH:
            raise ValueError("正文不能为空")
        if len(normalized) > post_service.CONTENT_MAX_LENGTH:
            raise ValueError(f"正文最长 {post_service.CONTENT_MAX_LENGTH} 个字")
        return normalized


class LikeState(BaseModel):
    """点赞接口的响应。

    回传**当前状态**而不只是「操作成功」：客户端点完要立刻把爱心和
    数字改对，只回一个 204 的话它只能自己猜加一还是减一。
    """

    like_count: int
    is_liked: bool
