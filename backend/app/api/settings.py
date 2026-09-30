"""个性化设置路由。对应 docs/API.md 第 8 节。

本层只做三件事：解析参数 → 调用 service → 包装成响应结构。

**两个接口都要求登录**：设置是跟着账号走的，没有账号就没有
「我的设置」可言。这也意味着未登录用户看到的首页永远是全模块 ——
默认就是把内容都给他看，不因为没登录而少给。
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.api.deps import get_current_user
from app.database.session import get_db
from app.models.user import User
from app.schemas.settings import SettingsOut, SettingsUpdate
from app.services.personalization import settings_service

router = APIRouter(prefix="/api/settings", tags=["个性化"])


@router.get("", response_model=SettingsOut, summary="获取个性化设置")
def read_settings(
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> SettingsOut:
    """取当前用户的设置。

    **从没设置过的用户拿到的是默认值，不是 404。**
    设置页是「进去看看现在是什么样」，绝大多数人是第一次打开 ——
    在这里回 404 等于要求客户端自己编一套默认值，
    而后端一旦改了默认值，两边的表现就对不上了。
    """
    return SettingsOut.from_view(settings_service.get_view(db, user_id=user.id))


@router.put(
    "",
    response_model=SettingsOut,
    summary="更新个性化设置",
    responses={
        404: {"description": "关注列表里有不存在的分类"},
        422: {"description": "首页模块键无法识别"},
    },
)
def update_settings(
    payload: SettingsUpdate,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> SettingsOut:
    """更新设置。只改传了的字段，其余保持原样。

    保存成功后返回**完整的最新设置**，客户端据此刷新界面，
    不必再发一次 GET。

    校验分两种错，因为它们的成因不同：

    · 分类不存在 → `404`。与 `POST /api/posts` 对分类的处理保持一致：
      它是对一个**已存在的资源**的引用，引用不存在就是 404。
    · 模块键不认识 → `422`。它是请求体里的一个枚举值写错了，
      和 `{"title": ""}` 属于同一类，是该请求本身不合法。

    两种都把出问题的取值**写进 detail**：只回一句「参数不对」，
    客户端拿着一个五项数组无从下手。
    """
    # exclude_unset：只取客户端**真的传了**的字段。
    #
    # 三个字段的默认值都是 None，所以这个接口上开不开它结果一样 ——
    # 但意图不一样：`data` 表示「这次请求说了什么」，
    # 而不是「请求体按 schema 展开后长什么样」。
    # 将来若给某个字段改成非 None 的默认值（比如 notify_enabled 默认 True），
    # 少了这一行就会变成「每次 PUT 都顺手把它重置成默认值」。
    data = payload.model_dump(exclude_unset=True)
    followed_categories = data.get("followed_categories")
    home_modules = data.get("home_modules")

    if followed_categories is not None:
        missing = settings_service.unknown_category_ids(db, followed_categories)
        if missing:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="分类不存在：" + "、".join(str(item) for item in missing),
            )

    if home_modules is not None:
        unknown = settings_service.unknown_modules(home_modules)
        if unknown:
            raise HTTPException(
                # 用字面量而不是 status.HTTP_422_*：那两个常量名
                # （UNPROCESSABLE_ENTITY / UNPROCESSABLE_CONTENT）
                # 在新版 Starlette 里互换了名字，写死 422 与 main.py 的
                # 全局校验处理器保持一致，也不会随版本改名而报 deprecation。
                status_code=422,
                detail="首页模块不存在：" + "、".join(unknown),
            )

    view = settings_service.update_settings(
        db,
        user_id=user.id,
        followed_categories=followed_categories,
        home_modules=home_modules,
        notify_enabled=data.get("notify_enabled"),
    )
    return SettingsOut.from_view(view)
