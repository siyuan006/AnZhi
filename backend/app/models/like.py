"""点赞表模型。对应 docs/DATABASE.md 3.8。"""

from __future__ import annotations

from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, Integer, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.database.base import Base, utcnow


class Like(Base):
    """帖子点赞。

    由 UNIQUE(post_id, user_id) 保证「同一用户对同一帖子只能点赞一次」。
    业务层的取消点赞就是删除这条记录，不需要额外的状态字段。
    """

    __tablename__ = "likes"
    __table_args__ = (
        UniqueConstraint("post_id", "user_id", name="uq_like_post_user"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    post_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("posts.id"), nullable=False, index=True
    )
    user_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("users.id"), nullable=False, index=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime, nullable=False, default=utcnow
    )

    def __repr__(self) -> str:
        return f"<Like post={self.post_id} user={self.user_id}>"
