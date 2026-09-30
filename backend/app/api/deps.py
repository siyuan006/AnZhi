"""公共请求依赖：从 Authorization 头解析出当前用户。

**这里的规则直接决定哪些能力需要登录**（docs/API.md 第 11 节）。
第十一阶段采用的原则：

    浏览知识、搜索、AI 问答 —— **不需要登录**
    收藏、历史记录          —— 需要登录

原因不只是「按文档实现」：安知是安全科普应用，
用户可能在起火、有人触电的当口打开它。任何一道登录墙都会
延误他拿到处置方法 —— 这是**安全问题，不是体验问题**。
因此需要身份的功能才要求身份，其余一律放开。
"""

from __future__ import annotations

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from app.database.session import get_db
from app.models.user import User
from app.services.auth import auth_service, tokens

# auto_error=False：没有 Authorization 头时**不自动抛 401**，
# 而是把 None 交给下面的依赖自行判断。
# 自动抛错会让「可选登录」的接口（如记录浏览历史）无法实现。
_bearer = HTTPBearer(auto_error=False)

_UNAUTHORIZED_HEADERS = {"WWW-Authenticate": "Bearer"}


def _user_from_credentials(
    db: Session, credentials: HTTPAuthorizationCredentials | None
) -> User | None:
    if credentials is None:
        return None

    user_id = tokens.read_user_id(credentials.credentials)
    if user_id is None:
        return None

    # token 合法不代表用户还在。用户被删除后，旧 token 在过期前
    # 依然能通过签名校验 —— 必须回数据库确认一次。
    return auth_service.get_user(db, user_id)


def get_current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer),
    db: Session = Depends(get_db),
) -> User:
    """要求已登录；未登录或 token 无效时抛 401。"""
    user = _user_from_credentials(db, credentials)
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="请先登录",
            headers=_UNAUTHORIZED_HEADERS,
        )
    return user


def get_optional_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer),
    db: Session = Depends(get_db),
) -> User | None:
    """允许匿名访问；带了有效 token 就返回用户，否则返回 None。

    用于「登录与否都能用，登录后多一个副作用」的接口 ——
    目前只有记录浏览历史。
    """
    return _user_from_credentials(db, credentials)
