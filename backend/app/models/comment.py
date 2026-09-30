"""评论表模型。对应 docs/DATABASE.md 3.7。"""

from __future__ import annotations

from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, Index, Integer, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database.base import Base, utcnow
from app.models.user import User


class Comment(Base):
    """帖子评论。

    `parent_id` 指向同表的另一条评论，用于二级回复。
    V1.0 只要求「帖子 + 评论」，二级回复是预留能力：
    字段先建好，界面与接口不实现（PROJECT_SPEC 第二十节）。
    """

    __tablename__ = "comments"
    __table_args__ = (Index("ix_comments_post_created", "post_id", "created_at"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    post_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("posts.id"), nullable=False, index=True
    )
    user_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("users.id"), nullable=False, index=True
    )
    content: Mapped[str] = mapped_column(Text, nullable=False)
    parent_id: Mapped[int | None] = mapped_column(
        Integer, ForeignKey("comments.id"), nullable=True, default=None
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime, nullable=False, default=utcnow
    )

    author: Mapped["User"] = relationship(lazy="joined")

    @property
    def author_name(self) -> str:
        return self.author.nickname or self.author.username

    def __repr__(self) -> str:
        return f"<Comment id={self.id} post={self.post_id}>"
