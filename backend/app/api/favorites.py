"""收藏路由。对应 docs/API.md 第 5 节。

本层只做三件事：解析参数 → 调用 service → 包装成响应结构。

**这里的每个接口都要求登录**，且所有查询都以 `user.id` 为条件 ——
收藏是「这份数据属于谁」的问题，是整个应用里少数几个真的需要
问「你是谁」的地方（docs/API.md 第 11 节）。
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Query, Response, status
from sqlalchemy.orm import Session

from app.api.deps import get_current_user
from app.database.session import get_db
from app.models.user import User
from app.schemas.common import Page
from app.schemas.favorite import FavoriteCreate, FavoriteItem, FavoriteOut
from app.services.knowledge import favorite_service

router = APIRouter(prefix="/api/favorites", tags=["收藏"])

#: 与 `GET /api/knowledge/{id}` 用**同一句话**。
#: 两种说法（「知识不存在」/「无权访问」）会让外部能区分
#: 「这条内容不存在」和「这条内容存在但没发布」。
_KNOWLEDGE_NOT_FOUND = "知识不存在或未发布"


@router.get("", response_model=Page[FavoriteItem], summary="我的收藏")
def list_favorites(
    page: int = Query(1, ge=1, description="页码"),
    page_size: int = Query(20, ge=1, le=100, description="每页条数"),
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Page[FavoriteItem]:
    """分页返回当前用户的收藏，按收藏时间倒序。

    只返回**仍可见**（已发布）的知识。收藏之后内容被撤下审核时，
    列表里不会留下一条点不开的入口 —— 代价是 `total` 会小于
    数据库里的收藏行数，这是刻意的：那个数字对用户没有意义。
    """
    total = favorite_service.count_favorites(db, user_id=user.id)
    items = favorite_service.list_favorites(
        db, user_id=user.id, page=page, page_size=page_size
    )

    return Page[FavoriteItem](
        total=total,
        page=page,
        page_size=page_size,
        items=[FavoriteItem.from_model(item) for item in items],
    )


@router.post(
    "",
    response_model=FavoriteOut,
    status_code=status.HTTP_201_CREATED,
    summary="收藏知识",
    responses={
        200: {"description": "之前已收藏过，返回那条已有记录（幂等）"},
        404: {"description": "知识不存在或未发布"},
    },
)
def add_favorite(
    payload: FavoriteCreate,
    response: Response,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> FavoriteOut:
    """收藏一篇知识。

    **幂等**（docs/API.md 第 5 节要求二选一，这里选定幂等）：
    重复收藏不报错，返回已有记录。新建时是 `201`，
    已经收藏过时是 `200` —— 用状态码如实区分「这次真的建了」和
    「之前就有了」，而不是把两种情况都报成 201。
    """
    result = favorite_service.add_favorite(
        db, user_id=user.id, knowledge_id=payload.knowledge_id
    )
    if not result.ok:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail=_KNOWLEDGE_NOT_FOUND
        )

    if not result.created:
        response.status_code = status.HTTP_200_OK

    assert result.favorite is not None  # result.ok 已保证
    return FavoriteOut.model_validate(result.favorite)


@router.delete(
    "/{knowledge_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    response_class=Response,
    summary="取消收藏",
)
def remove_favorite(
    knowledge_id: int,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> None:
    """取消收藏。**幂等**：本来就没收藏也返回 204。

    这里不返回 404。用户点「取消收藏」，想要的结果是
    「这条不在我的收藏里」—— 它已经成立了，没什么可报错的。
    返回 404 只会让客户端去处理一个「其实已经成功」的失败分支。
    """
    favorite_service.remove_favorite(
        db, user_id=user.id, knowledge_id=knowledge_id
    )
