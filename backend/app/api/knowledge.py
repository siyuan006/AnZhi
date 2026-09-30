"""知识系统路由。对应 docs/API.md 第 4 节。

本层只做三件事：解析参数 → 调用 service → 包装成响应结构。
"""

from __future__ import annotations

from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session

from app.database.session import get_db
from app.schemas.common import Page
from app.schemas.knowledge import CategoryOut, KnowledgeDetail, KnowledgeListItem
from app.services.knowledge import knowledge_service

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
    page: int = Query(1, ge=1, description="页码"),
    page_size: int = Query(20, ge=1, le=100, description="每页条数"),
    db: Session = Depends(get_db),
) -> Page[KnowledgeListItem]:
    """分页返回**已发布**的知识卡片。

    未发布内容不会出现在结果里（PROJECT_SPEC 第十五节），
    因此内容审核状态会直接影响这个接口的返回条数。
    """
    total = knowledge_service.count_knowledge(
        db, category_id=category_id, risk_level=risk_level, keyword=keyword
    )
    items = knowledge_service.list_knowledge(
        db,
        category_id=category_id,
        risk_level=risk_level,
        keyword=keyword,
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
    db: Session = Depends(get_db),
) -> KnowledgeDetail:
    """返回知识详情。

    尚未实现（按阶段推进，不做假实现）：

    - **写入浏览历史**：docs/API.md 提到详情接口会记录浏览历史，
      但历史记录必须归属到具体用户，而登录体系属于阶段 11。
      在此之前没有可靠的 user_id 可写，因此不写 —— 阶段 11 补上。
    - **累加 view_count**：浏览量统计属于阶段 10（知识系统），
      且会让 GET 变成写操作，同样留到那时一起处理。
    """
    item = knowledge_service.get_knowledge(db, knowledge_id)
    if item is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="知识不存在或未发布",
        )
    return KnowledgeDetail.from_model(item)
