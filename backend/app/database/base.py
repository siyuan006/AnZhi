"""SQLAlchemy 声明式基类与公共字段。

所有数据库模型都继承 `Base`，需要 created_at / updated_at 的再混入
`TimestampMixin`（见 docs/DATABASE.md 第 1 节）。
"""

from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy import DateTime
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column


def utcnow() -> datetime:
    """当前 UTC 时间（**不带时区信息**）。

    为什么刻意去掉 tzinfo：
    SQLite 没有原生时区类型，带时区的时间存进去、再读出来一定变成 naive。
    如果写入时是 aware、读出来是 naive，两者一比较就会抛
    `can't compare offset-naive and offset-aware datetimes`。
    因此全项目统一使用 naive UTC，避免这类只在运行期才暴露的坑。
    """
    return datetime.now(timezone.utc).replace(tzinfo=None)


class Base(DeclarativeBase):
    """所有数据库模型的基类。"""


class TimestampMixin:
    """创建时间 / 更新时间。

    同时带 created_at 与 updated_at 的表混入本类
    （users / knowledge / posts / user_settings）；
    只有 created_at 的表在各自模型里单独声明。
    """

    created_at: Mapped[datetime] = mapped_column(
        DateTime,
        nullable=False,
        default=utcnow,
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime,
        nullable=False,
        default=utcnow,
        onupdate=utcnow,
    )
