"""认证路由。对应 docs/API.md 第 11 节。

本层只做三件事：解析参数 → 调用 service → 把业务结果翻译成状态码。
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.api.deps import get_current_user
from app.config.settings import settings
from app.database.session import get_db
from app.models.user import User
from app.schemas.auth import LoginRequest, RegisterRequest, TokenOut, UserOut
from app.schemas.common import ErrorResponse
from app.services.auth import auth_service
from app.services.auth.auth_service import AuthResult

router = APIRouter(prefix="/api/auth", tags=["认证"])


def _to_token_out(result: AuthResult) -> TokenOut:
    """把成功的业务结果转成响应体。

    调用前必须确认 `result.ok`，否则这里会拿 None 拼出一个坏响应 ——
    与其静默地返回半截数据，不如让它在这里就崩掉。
    """
    if result.user is None or result.token is None:  # pragma: no cover
        raise RuntimeError("_to_token_out 被用在了失败的 AuthResult 上")

    return TokenOut(
        access_token=result.token,
        expires_in=settings.jwt_expire_minutes * 60,
        user=UserOut.model_validate(result.user),
    )


@router.post(
    "/register",
    response_model=TokenOut,
    status_code=status.HTTP_201_CREATED,
    summary="注册",
    responses={
        400: {"model": ErrorResponse, "description": "用户名或密码不符合要求"},
        409: {"model": ErrorResponse, "description": "用户名已被注册"},
    },
)
def register(
    payload: RegisterRequest,
    db: Session = Depends(get_db),
) -> TokenOut:
    """创建账号并直接返回 token（注册完还要再登录一次是多余的一步）。

    **注意：不要在日志里打印 payload** —— 里面有明文密码。
    """
    result = auth_service.register(
        db,
        username=payload.username,
        password=payload.password,
        nickname=payload.nickname,
    )
    if result.ok:
        return _to_token_out(result)

    # 「已被注册」用 409（资源冲突），其余校验失败用 400。
    # 用户看到的都是那句具体的中文说明，状态码只影响客户端的处理分支。
    code = (
        status.HTTP_409_CONFLICT
        if result.problem == "该用户名已被注册"
        else status.HTTP_400_BAD_REQUEST
    )
    raise HTTPException(status_code=code, detail=result.problem)


@router.post(
    "/login",
    response_model=TokenOut,
    summary="登录",
    responses={401: {"model": ErrorResponse, "description": "用户名或密码不正确"}},
)
def login(payload: LoginRequest, db: Session = Depends(get_db)) -> TokenOut:
    """校验用户名与密码，成功后签发 token。

    **注意：不要在日志里打印 payload** —— 里面有明文密码。
    """
    result = auth_service.login(
        db, username=payload.username, password=payload.password
    )
    if result.ok:
        return _to_token_out(result)

    raise HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail=result.problem,
        headers={"WWW-Authenticate": "Bearer"},
    )


@router.get(
    "/me",
    response_model=UserOut,
    summary="当前登录用户",
    responses={401: {"model": ErrorResponse, "description": "未登录或 token 已失效"}},
)
def me(user: User = Depends(get_current_user)) -> UserOut:
    """返回当前 token 对应的用户。

    App 启动时用它验证本地存的 token 是否还有效 ——
    唯一能确认「token 没过期、用户还在」的办法是问一次服务端，
    客户端自己解析 `exp` 只是省一次请求，挡不住用户已被删除的情况。
    """
    return UserOut.model_validate(user)
