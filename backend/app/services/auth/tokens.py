"""JWT 签发与校验（docs/API.md 第 11 节：V1.0 采用简单 JWT 认证）。

只做「签发」和「解析」两件事，不碰数据库 —— 因此这里不关心
用户是否存在、是否被禁用，那些属于 auth_service 的判断。
"""

from __future__ import annotations

from datetime import timedelta

import jwt

from app.config.settings import settings
from app.database.base import utcnow

# token 里只放用户 id（`sub`）和过期时间（`exp`）。
# 刻意**不放用户名、昵称、邮箱**：token 是客户端可读的 base64，
# 放进去等于把这些信息交给了任何拿到 token 的人；
# 而且这些字段一旦修改，旧 token 里就是过期数据。
SUBJECT_KEY = "sub"


def create_access_token(user_id: int) -> str:
    """签发一枚只代表「这个 id 的用户已登录」的 token。"""
    now = utcnow()
    payload = {
        SUBJECT_KEY: str(user_id),
        "iat": now,
        "exp": now + timedelta(minutes=settings.jwt_expire_minutes),
    }
    return jwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_algorithm)


def read_user_id(token: str) -> int | None:
    """从 token 解出用户 id；token 无效 / 过期 / 被改过时返回 None。

    这里**把各类失败统一收敛成 None**，因为对调用方来说它们结论相同：
    这次请求没有可信的身份。区分「签名不对」和「已过期」只会
    把「这个 token 是不是伪造的」这类信息泄露给攻击者。
    """
    try:
        payload = jwt.decode(
            token,
            settings.jwt_secret,
            # 显式指定算法白名单。不指定的话，历史上出现过
            # 攻击者把 alg 改成 none 或换成非对称算法来绕过验签的漏洞。
            algorithms=[settings.jwt_algorithm],
        )
    except jwt.PyJWTError:
        return None

    raw = payload.get(SUBJECT_KEY)
    if raw is None:
        return None

    try:
        return int(raw)
    except (TypeError, ValueError):
        return None
