"""知识卡片表模型。对应 docs/DATABASE.md 3.3 与 PROJECT_SPEC 第十六节。"""

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

#: 允许的风险等级，与前端 RiskLevel 枚举、PROJECT_SPEC 第十节一致
RISK_LEVELS: tuple[str, ...] = ("low", "medium", "high")


class Knowledge(Base, TimestampMixin):
    """安全知识卡片。

    内容安全（PROJECT_SPEC 第十五节）：
        知识卡片的流程是「AI 生成初稿 → 人工审核 → 发布」。
        `is_published` 默认 `False`，**未经人工审核的内容不得对外可见**，
        高风险安全知识尤其禁止自动发布。
    """

    __tablename__ = "knowledge"
    __table_args__ = (
        # 风险等级只允许三个取值，防止写入 'HIGH'、'高危' 之类的脏数据
        CheckConstraint(
            "risk_level IN ('low', 'medium', 'high')",
            name="ck_knowledge_risk_level",
        ),
        # docs/DATABASE.md 第 4 节的索引要求：
        # 分类筛选、时间排序、按风险等级取数
        Index("ix_knowledge_category_id", "category_id"),
        Index("ix_knowledge_created_at", "created_at"),
        Index("ix_knowledge_risk_level", "risk_level"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    title: Mapped[str] = mapped_column(String(200), nullable=False, index=True)
    category_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("categories.id"), nullable=False
    )
    summary: Mapped[str | None] = mapped_column(String(500), default=None)
    content: Mapped[str] = mapped_column(Text, nullable=False)
    risk_level: Mapped[str] = mapped_column(
        String(10), nullable=False, default="low", server_default=text("'low'")
    )
    image_url: Mapped[str | None] = mapped_column(String(255), default=None)
    source: Mapped[str | None] = mapped_column(String(500), default=None)
    author: Mapped[str | None] = mapped_column(String(50), default=None)
    view_count: Mapped[int] = mapped_column(
        Integer, nullable=False, default=0, server_default=text("0")
    )
    # 审核发布开关：默认不发布，必须在数据库中显式置为 1 才会对外可见
    is_published: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default=text("0")
    )

    # lazy="joined"：取知识卡片时顺带 JOIN 出分类。
    # 列表接口需要显示分类名，若用默认的懒加载会产生 N+1 次查询
    # （20 条数据 21 次 SQL）。这里的 JOIN 成本远低于多跑 20 次查询。
    category: Mapped["Category"] = relationship(lazy="joined")

    def __repr__(self) -> str:
        return (
            f"<Knowledge id={self.id} title={self.title!r} "
            f"published={self.is_published}>"
        )
