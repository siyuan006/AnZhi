"""用户表模型。对应 docs/DATABASE.md 3.1。"""

from __future__ import annotations

from sqlalchemy import Integer, String, text
from sqlalchemy.orm import Mapped, mapped_column

from app.database.base import Base, TimestampMixin


class User(Base, TimestampMixin):
    """用户。

    安全要求（docs/DATABASE.md 3.1）：
        `password_hash` 只允许存放 bcrypt / argon2 等算法产生的**哈希值**，
        禁止存储明文密码，也禁止把该字段打进日志。
    """

    __tablename__ = "users"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    username: Mapped[str] = mapped_column(
        String(50), unique=True, nullable=False, index=True
    )
    email: Mapped[str | None] = mapped_column(
        String(120), unique=True, index=True, default=None
    )
    password_hash: Mapped[str] = mapped_column(String(255), nullable=False)
    nickname: Mapped[str | None] = mapped_column(String(50), default=None)
    avatar_url: Mapped[str | None] = mapped_column(String(255), default=None)
    study_days: Mapped[int] = mapped_column(
        Integer, nullable=False, default=0, server_default=text("0")
    )

    def __repr__(self) -> str:
        # 刻意不输出 password_hash，避免哈希值随日志外泄
        return f"<User id={self.id} username={self.username!r}>"
