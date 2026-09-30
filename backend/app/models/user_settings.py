"""用户设置表模型。对应 docs/DATABASE.md 3.9。

支撑 PROJECT_SPEC 第十九节「个性化首页」与第四十二节「个性化」：
关注分类、首页模块显示配置、通知开关。
"""

from __future__ import annotations

from sqlalchemy import JSON, Boolean, ForeignKey, Integer, text
from sqlalchemy.ext.mutable import MutableList
from sqlalchemy.orm import Mapped, mapped_column

from app.database.base import Base, TimestampMixin


class UserSettings(Base, TimestampMixin):
    """用户个性化设置，与用户一对一。"""

    __tablename__ = "user_settings"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("users.id"), nullable=False, unique=True
    )

    # 必须用 MutableList 包一层：
    # SQLAlchemy 默认无法感知 JSON 字段的「原地修改」。
    # 若直接写 settings.followed_categories.append(1)，
    # 不套 MutableList 的话这次修改**不会被写进数据库**，而且不报任何错 ——
    # 这是最典型的一类「代码看起来对、数据就是没存上」的 bug。
    followed_categories: Mapped[list[int]] = mapped_column(
        MutableList.as_mutable(JSON),
        nullable=False,
        default=list,
        server_default=text("'[]'"),
    )
    home_modules: Mapped[list[str]] = mapped_column(
        MutableList.as_mutable(JSON),
        nullable=False,
        default=list,
        server_default=text("'[]'"),
    )

    notify_enabled: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=True, server_default=text("1")
    )

    def __repr__(self) -> str:
        return f"<UserSettings user={self.user_id}>"
