"""知识系统路由。对应 docs/API.md 第 4 节。

本层只做三件事：解析参数 → 调用 service → 包装成响应结构。
"""

from __future__ import annotations

from typing import Annotated, Literal

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import Field
from sqlalchemy.orm import Session

from app.api.deps import get_optional_user
from app.database.session import get_db
from app.models.user import User
from app.schemas.common import Page
from app.schemas.knowledge import (
    CategoryOut,
    KnowledgeDetail,
    KnowledgeListItem,
    ViewCountOut,
)
from app.services.knowledge import (
    favorite_service,
    history_service,
    knowledge_service,
)

router = APIRouter(tags=["知识系统"])


@router.get(
    "/api/categories",
    response_model=list[CategoryOut],
    summary="获取六大分类",
)
def list_categories(db: Session = Depends(get_db)) -> list[CategoryOut]:
    categories = knowledge_service.list_categories(db)
    return [CategoryOut.model_validate(item) for item in categories]


@router.get(
    "/api/knowledge",
    response_model=Page[KnowledgeListItem],
    summary="知识列表",
)
def list_knowledge(
    category_id: int | None = Query(None, ge=1, description="按分类筛选"),
    risk_level: Literal["low", "medium", "high"] | None = Query(
        None, description="按风险等级筛选"
    ),
    keyword: str | None = Query(None, max_length=50, description="标题/简介模糊搜索"),
    # `ge=1` 必须写在**元素**上：写成 `Query(None, ge=1)` 时 FastAPI 会把
    # 整个列表当成一个值去比大小，直接抛 TypeError → 500。
    prefer_categories: Annotated[
        list[Annotated[int, Field(ge=1)]] | None,
        Query(description="关注分类的 id，可重复传；只调整排序，不作为筛选"),
    ] = None,
    page: int = Query(1, ge=1, description="页码"),
    page_size: int = Query(20, ge=1, le=100, description="每页条数"),
    db: Session = Depends(get_db),
) -> Page[KnowledgeListItem]:
    """分页返回**已发布**的知识卡片。

    未发布内容不会出现在结果里（PROJECT_SPEC 第十五节），
    因此内容审核状态会直接影响这个接口的返回条数。

    `prefer_categories` 是**排序偏好而不是筛选条件**：给了它，
    这些分类的内容排在前面，其余的照样返回，`total` 也不变 ——
    关注一个领域不该让用户看不到别的领域。
    """
    total = knowledge_service.count_knowledge(
        db, category_id=category_id, risk_level=risk_level, keyword=keyword
    )
    items = knowledge_service.list_knowledge(
        db,
        category_id=category_id,
        risk_level=risk_level,
        keyword=keyword,
        prefer_category_ids=prefer_categories,
        page=page,
        page_size=page_size,
    )

    return Page[KnowledgeListItem](
        total=total,
        page=page,
        page_size=page_size,
        items=[KnowledgeListItem.from_model(item) for item in items],
    )


@router.get(
    "/api/knowledge/{knowledge_id}",
    response_model=KnowledgeDetail,
    summary="知识详情",
    responses={404: {"description": "知识不存在或未发布"}},
)
def get_knowledge(
    knowledge_id: int,
    user: User | None = Depends(get_optional_user),
    db: Session = Depends(get_db),
) -> KnowledgeDetail:
    """返回知识详情。

    **本接口不累加浏览量**，也不会写入浏览历史 —— 它是一个纯读接口。
    这两件事都由客户端在用户真正打开详情页时调用
    `POST /api/knowledge/{id}/view` 完成。

    带有效 token 时会在响应里带上 `is_favorited`，供详情页把收藏按钮
    初始化成正确的状态；匿名访问照常返回 200，`is_favorited` 恒为 False。
    **匿名仍然能读到全部内容** —— 这是刻意的（docs/API.md 第 11 节）：
    安知是安全科普应用，用户可能在起火、有人触电的当口打开它。
    """
    item = knowledge_service.get_knowledge(db, knowledge_id)
    if item is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="知识不存在或未发布",
        )

    return KnowledgeDetail.from_model(
        item,
        is_favorited=favorite_service.is_favorited(
            db,
            user_id=user.id if user else None,
            knowledge_id=knowledge_id,
        ),
    )


@router.post(
    "/api/knowledge/{knowledge_id}/view",
    response_model=ViewCountOut,
    summary="记录一次浏览",
    responses={404: {"description": "知识不存在或未发布"}},
)
def record_view(
    knowledge_id: int,
    user: User | None = Depends(get_optional_user),
    db: Session = Depends(get_db),
) -> ViewCountOut:
    """把浏览量加一，返回最新的浏览量；已登录用户顺带记一条浏览历史。

    单独做成写接口而不是塞进 GET 详情里：

    - GET 应当是幂等、可缓存的。带副作用的 GET 会被浏览器预取、
      爬虫和失败重试各加一次，统计出来的数字没有意义。
    - 「用户打开了详情页」是客户端才知道的信息，由客户端明确告知
      比服务端猜测可靠。

    未发布内容同样返回 404 —— 直接对未发布的 id 自增，
    等于对外确认了这条内容存在。

    **浏览历史挂在同一个动作上**（阶段 11c），但它需要身份：
    未登录时只计数、不写历史，因此这里用的是 `get_optional_user`
    而不是 `get_current_user` —— 匿名浏览知识是允许的，
    不会因为「记不了历史」就把这次浏览变成 401。
    """
    count = knowledge_service.increment_view_count(db, knowledge_id)
    if count is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="知识不存在或未发布",
        )

    # 放在计数之后：走到这里说明可见性已经确认过了，
    # 不必再查一次「这条能不能看」。
    # 并发下两个请求抢同一条历史时，冲突在 service 内部被消化成
    # 「更新那一条」，不会冒成 500 —— 否则一次正常的浏览会变成错误页。
    if user is not None:
        history_service.record_view(
            db, user_id=user.id, knowledge_id=knowledge_id
        )

    return ViewCountOut(view_count=count)
