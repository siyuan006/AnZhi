"""认证相关的请求 / 响应结构。对应 docs/API.md 第 11 节。"""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict, Field


class RegisterRequest(BaseModel):
    """注册请求。

    这里**只做结构校验**（字段在不在、类型对不对）。
    「用户名是否已被占用」「密码够不够长」属于业务规则，
    放在 auth_service 里，保证同一套规则在注册和登录两条路径上一致。
    """

    username: str = Field(..., description="用户名，3-20 个字符")
    password: str = Field(..., description="密码，至少 8 位且不超过 72 字节")
    nickname: str | None = Field(default=None, description="昵称，可空")


class LoginRequest(BaseModel):
    username: str
    password: str


class UserOut(BaseModel):
    """对外暴露的用户信息。

    刻意**不包含 `password_hash`**，也不包含 email ——
    响应模型是白名单而不是黑名单：新增字段时默认不外泄，
    比「记得把敏感字段排除掉」可靠得多。
    """

    model_config = ConfigDict(from_attributes=True)

    id: int
    username: str
    nickname: str | None = None
    avatar_url: str | None = None
    study_days: int = 0


class TokenOut(BaseModel):
    """登录 / 注册成功的响应。"""

    access_token: str
    token_type: str = "bearer"
    expires_in: int = Field(..., description="有效期（秒）")
    user: UserOut
