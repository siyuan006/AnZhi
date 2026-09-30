"""收藏表模型。对应 docs/DATABASE.md 3.4。"""

from __future__ import annotations

from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, Index, Integer, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.database.base import Base, utcnow


class Favorite(Base):
    """用户收藏的知识卡片。"""

    __tablename__ = "favorites"
    __table_args__ = (
        # 防止重复收藏：同一个用户对同一篇知识只能有一条收藏记录。
        # 有这条约束后，「重复收藏」在数据库层直接失败，
        # 而不是靠业务代码每次记得先查一遍。
        UniqueConstraint("user_id", "knowledge_id", name="uq_favorite_user_knowledge"),
        Index("ix_favorites_user_created", "user_id", "created_at"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("users.id"), nullable=False, index=True
    )
    knowledge_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("knowledge.id"), nullable=False, index=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime, nullable=False, default=utcnow
    )

    def __repr__(self) -> str:
        return f"<Favorite user={self.user_id} knowledge={self.knowledge_id}>"
