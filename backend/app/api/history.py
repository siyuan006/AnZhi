"""浏览历史路由。对应 docs/API.md 第 6 节。

本层只做三件事：解析参数 → 调用 service → 包装成响应结构。

**这里的每个接口都要求登录**，且所有查询都以 `user.id` 为条件 ——
历史记录和收藏一样，是「这份数据属于谁」的问题。

注意历史记录的**写入**不在这里：它不是用户主动发起的动作，
而是浏览知识时的副作用，因此挂在 `POST /api/knowledge/{id}/view` 上
（那里带的是可选登录身份，匿名浏览不写任何人的历史）。
本模块只负责读和删。
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, Query, Response, status
from sqlalchemy.orm import Session

from app.api.deps import get_current_user
from app.database.session import get_db
from app.models.user import User
from app.schemas.common import Page
from app.schemas.history import HistoryItem
from app.services.knowledge import history_service

router = APIRouter(prefix="/api/history", tags=["浏览历史"])


@router.get("", response_model=Page[HistoryItem], summary="浏览历史")
def list_history(
    page: int = Query(1, ge=1, description="页码"),
    page_size: int = Query(20, ge=1, le=100, description="每页条数"),
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Page[HistoryItem]:
    """分页返回当前用户的浏览历史，按最近浏览倒序。

    只返回**仍可见**（已发布）的知识。浏览过、之后被撤回的内容
    不会留在列表里 —— 一条点不开的入口对用户没有意义，
    代价是 `total` 可能小于数据库里的历史行数。
    """
    total = history_service.count_history(db, user_id=user.id)
    items = history_service.list_history(
        db, user_id=user.id, page=page, page_size=page_size
    )

    return Page[HistoryItem](
        total=total,
        page=page,
        page_size=page_size,
        items=[HistoryItem.from_model(row) for row in items],
    )


@router.delete(
    "",
    status_code=status.HTTP_204_NO_CONTENT,
    response_class=Response,
    summary="清空浏览历史",
)
def clear_history(
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> None:
    """清空当前用户的全部浏览历史。

    即使本来就是空的也返回 204 —— 用户要的是「我的历史是空的」，
    这个状态已经成立了。
    """
    history_service.clear_all(db, user_id=user.id)


@router.delete(
    "/{knowledge_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    response_class=Response,
    summary="删除单条浏览历史",
)
def remove_history(
    knowledge_id: int,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> None:
    """从历史里删掉一条。**幂等**：本来就没有也返回 204。

    与取消收藏同理，不返回 404：用户想要的结果是
    「这条不在我的历史里」，它已经成立了。
    """
    history_service.remove_one(db, user_id=user.id, knowledge_id=knowledge_id)
