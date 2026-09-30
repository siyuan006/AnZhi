"""社区帖子表模型。对应 docs/DATABASE.md 3.6。"""

from __future__ import annotations

from sqlalchemy import (
    Boolean,
    CheckConstraint,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    text,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database.base import Base, TimestampMixin
from app.models.category import Category
from app.models.user import User


class Post(Base, TimestampMixin):
    """社区帖子。

    注意与知识卡片的区别：
        knowledge.is_published 默认为 **False**（内容必须人工审核后发布），
        posts.is_published 默认为 **True**（用户自己发的帖子默认可见）。
        两者的默认值是刻意不同的，不要「顺手统一」。

    `like_count` / `comment_count` 是冗余计数字段（docs/DATABASE.md 3.6），
    用于列表排序时避免每次 COUNT(*)。
    它们由业务层在点赞 / 评论时同步维护，属于阶段 12 的工作。
    """

    __tablename__ = "posts"
    __table_args__ = (
        CheckConstraint("like_count >= 0", name="ck_posts_like_count"),
        CheckConstraint("comment_count >= 0", name="ck_posts_comment_count"),
        Index("ix_posts_created_at", "created_at"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("users.id"), nullable=False, index=True
    )
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    content: Mapped[str] = mapped_column(Text, nullable=False)
    # 可选：帖子可以不属于任何分类
    category_id: Mapped[int | None] = mapped_column(
        Integer, ForeignKey("categories.id"), nullable=True, default=None
    )
    like_count: Mapped[int] = mapped_column(
        Integer, nullable=False, default=0, server_default=text("0")
    )
    comment_count: Mapped[int] = mapped_column(
        Integer, nullable=False, default=0, server_default=text("0")
    )
    is_published: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=True, server_default=text("1")
    )

    # lazy="joined"：列表里每条都要显示作者署名与分类名，默认懒加载会 N+1。
    # 与 Knowledge.category、Favorite.knowledge 的处理保持一致。
    author: Mapped["User"] = relationship(lazy="joined")
    category: Mapped["Category | None"] = relationship(lazy="joined")

    @property
    def author_name(self) -> str:
        """对外显示的署名：昵称优先，没有昵称时退回用户名。"""
        return self.author.nickname or self.author.username

    def __repr__(self) -> str:
        return f"<Post id={self.id} title={self.title!r}>"