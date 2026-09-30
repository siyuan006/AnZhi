"""账号业务逻辑：注册、登录、按 id 取用户。

分层（PROJECT_SPEC 第五十二节）：api → services → models，单向。
本模块不认识 HTTP，也不抛 HTTPException ——
「用户名已存在」是业务结果，翻译成 409 是 api 层的事。
"""

from __future__ import annotations

from dataclasses import dataclass

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.models.user import User
from app.services.auth import passwords, tokens

USERNAME_MIN_CHARS = 3
USERNAME_MAX_CHARS = 20
NICKNAME_MAX_CHARS = 20


@dataclass(frozen=True)
class AuthResult:
    """一次成功认证的结果。

    `problem` 为 None 表示成功；否则它是一句可以直接展示给用户的中文。
    刻意**不用异常表达「用户名已存在」**这类业务失败：
    调用方每处都要 try，很容易漏掉一条分支而变成 500。
    """

    user: User | None = None
    token: str | None = None
    problem: str | None = None

    @property
    def ok(self) -> bool:
        return self.user is not None and self.token is not None


def _username_problem(username: str) -> str | None:
    if not username:
        return "用户名不能为空"
    if len(username) < USERNAME_MIN_CHARS:
        return f"用户名至少 {USERNAME_MIN_CHARS} 个字符"
    if len(username) > USERNAME_MAX_CHARS:
        return f"用户名最多 {USERNAME_MAX_CHARS} 个字符"
    return None


def register(
    db: Session,
    *,
    username: str,
    password: str,
    nickname: str | None = None,
) -> AuthResult:
    """注册并直接返回 token —— 注册完还要再登录一次是多余的一步。"""
    username = username.strip()
    nickname = (nickname or "").strip() or None

    if (problem := _username_problem(username)) is not None:
        return AuthResult(problem=problem)

    if (problem := passwords.password_problem(password)) is not None:
        return AuthResult(problem=problem)

    if nickname is not None and len(nickname) > NICKNAME_MAX_CHARS:
        return AuthResult(problem=f"昵称最多 {NICKNAME_MAX_CHARS} 个字符")

    if get_user_by_username(db, username) is not None:
        return AuthResult(problem="该用户名已被注册")

    user = User(
        username=username,
        nickname=nickname,
        password_hash=passwords.hash_password(password),
    )
    db.add(user)
    try:
        db.commit()
    except IntegrityError:
        # 上面刚查过一次，这里是并发下的兜底：
        # 两个请求同时注册同一个用户名时，只有数据库的唯一约束靠得住。
        db.rollback()
        return AuthResult(problem="该用户名已被注册")

    db.refresh(user)
    return AuthResult(user=user, token=tokens.create_access_token(user.id))


def login(db: Session, *, username: str, password: str) -> AuthResult:
    """校验用户名与口令。"""
    user = get_user_by_username(db, username.strip())

    if user is None or not passwords.verify_password(password, user.password_hash):
        # 用户名不存在与密码错误返回**同一句话**：
        # 分开提示等于提供了一个「这个用户名存不存在」的查询接口。
        return AuthResult(problem="用户名或密码不正确")

    return AuthResult(user=user, token=tokens.create_access_token(user.id))


def get_user_by_username(db: Session, username: str) -> User | None:
    return db.scalar(select(User).where(User.username == username))


def get_user(db: Session, user_id: int) -> User | None:
    return db.get(User, user_id)
