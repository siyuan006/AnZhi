"""分类表模型。对应 docs/DATABASE.md 3.2。

V1.0 固定六个分类（PROJECT_SPEC 第四节），初始化时写入种子数据。
分类的 id 必须与前端 frontend/lib/core/app_constants.dart 中的
`kCategories` 保持一致，否则前端按 id 过滤会取不到数据。
"""

from __future__ import annotations

from datetime import datetime

from sqlalchemy import DateTime, Integer, String, text
from sqlalchemy.orm import Mapped, mapped_column

from app.database.base import Base, utcnow


class Category(Base):
    """安全知识分类。"""

    __tablename__ = "categories"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String(50), unique=True, nullable=False)
    # slug 供前端路由与代码内引用使用，避免在代码里散落中文字面量
    slug: Mapped[str] = mapped_column(String(50), unique=True, nullable=False)
    icon: Mapped[str | None] = mapped_column(String(50), default=None)
    color: Mapped[str | None] = mapped_column(String(20), default=None)
    description: Mapped[str | None] = mapped_column(String(255), default=None)
    sort_order: Mapped[int] = mapped_column(
        Integer, nullable=False, default=0, server_default=text("0")
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime, nullable=False, default=utcnow
    )

    def __repr__(self) -> str:
        return f"<Category id={self.id} slug={self.slug!r}>"
