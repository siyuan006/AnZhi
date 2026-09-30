"""浏览历史表模型。对应 docs/DATABASE.md 3.5。"""

from __future__ import annotations

from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, Index, Integer, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database.base import Base, utcnow
from app.models.knowledge import Knowledge


class History(Base):
    """浏览历史。

    docs/DATABASE.md 3.5 规定：同一用户重复浏览同一篇知识时
    **更新 viewed_at，不新增记录**。

    这条规则如果只写在业务代码里，任何一处漏判都会产生重复历史。
    因此这里用 UNIQUE(user_id, knowledge_id) 把它固化到数据库层，
    业务层负责「存在则更新，不存在则插入」（upsert）。
    """

    __tablename__ = "histories"
    __table_args__ = (
        UniqueConstraint("user_id", "knowledge_id", name="uq_history_user_knowledge"),
        # 历史列表按「最近浏览」排序
        Index("ix_histories_user_viewed", "user_id", "viewed_at"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("users.id"), nullable=False, index=True
    )
    knowledge_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("knowledge.id"), nullable=False, index=True
    )
    viewed_at: Mapped[datetime] = mapped_column(
        DateTime, nullable=False, default=utcnow, index=True
    )

    # lazy="joined"：历史列表要显示标题和分类，若用默认懒加载会 N+1。
    # 与 Favorite.knowledge 的处理保持一致。
    knowledge: Mapped["Knowledge"] = relationship(lazy="joined")

    def __repr__(self) -> str:
        return f"<History user={self.user_id} knowledge={self.knowledge_id}>"
