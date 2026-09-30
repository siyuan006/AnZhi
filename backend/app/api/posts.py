"""社区路由。对应 docs/API.md 第 7 节。

本层只做三件事：解析参数 → 调用 service → 包装成响应结构。

阶段 12a 只实现**读**：列表与详情。
评论（12b）、点赞（12c）、发帖与删帖（12d）在后续补上，
因此这里暂时没有任何写接口。
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session

from app.database.session import get_db
from app.schemas.common import Page
from app.schemas.post import PostDetail, PostItem
from app.services.community import post_service

router = APIRouter(prefix="/api/posts", tags=["社区"])


@router.get("", response_model=Page[PostItem], summary="帖子列表")
def list_posts(
    category_id: int | None = Query(None, ge=1, description="按分类筛选"),
    keyword: str | None = Query(None, max_length=50, description="标题/正文模糊搜索"),
    page: int = Query(1, ge=1, description="页码"),
    page_size: int = Query(20, ge=1, le=100, description="每页条数"),
    db: Session = Depends(get_db),
) -> Page[PostItem]:
    """分页返回帖子，按发布时间倒序。

    **不需要登录。** 社区内容是公开的，浏览它没有理由要求身份 ——
    这与知识库的处理一致（PROJECT_SPEC 第二十节、docs/API.md 第 11 节）。
    """
    total = post_service.count_posts(db, category_id=category_id, keyword=keyword)
    items = post_service.list_posts(
        db,
        category_id=category_id,
        keyword=keyword,
        page=page,
        page_size=page_size,
    )

    return Page[PostItem](
        total=total,
        page=page,
        page_size=page_size,
        items=[PostItem.from_model(item) for item in items],
    )


@router.get(
    "/{post_id}",
    response_model=PostDetail,
    summary="帖子详情",
    responses={404: {"description": "帖子不存在或已删除"}},
)
def get_post(
    post_id: int,
    db: Session = Depends(get_db),
) -> PostDetail:
    """返回帖子全文。同样不需要登录。

    详情页的评论列表是另一个接口（阶段 12b），
    本接口只返回 `comment_count` 这个计数。
    """
    item = post_service.get_post(db, post_id)
    if item is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="帖子不存在或已删除",
        )

    return PostDetail.from_model(item)
