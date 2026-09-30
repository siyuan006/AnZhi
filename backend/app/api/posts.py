"""社区路由。对应 docs/API.md 第 7 节。

本层只做三件事：解析参数 → 调用 service → 包装成响应结构。

已实现：列表与详情（12a）、评论的读与写（12b）、点赞与取消（12c）。
发帖与删帖（12d）在后续补上。
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Query, Response, status
from sqlalchemy.orm import Session

from app.api.deps import get_current_user, get_optional_user
from app.database.session import get_db
from app.models.user import User
from app.schemas.comment import CommentCreate, CommentItem
from app.schemas.common import Page
from app.schemas.post import LikeState, PostDetail, PostItem
from app.services.community import comment_service, like_service, post_service

router = APIRouter(prefix="/api/posts", tags=["社区"])


@router.get("", response_model=Page[PostItem], summary="帖子列表")
def list_posts(
    category_id: int | None = Query(None, ge=1, description="按分类筛选"),
    keyword: str | None = Query(None, max_length=50, description="标题/正文模糊搜索"),
    page: int = Query(1, ge=1, description="页码"),
    page_size: int = Query(20, ge=1, le=100, description="每页条数"),
    user: User | None = Depends(get_optional_user),
    db: Session = Depends(get_db),
) -> Page[PostItem]:
    """分页返回帖子，按发布时间倒序。

    **不需要登录。** 社区内容是公开的，浏览它没有理由要求身份 ——
    这与知识库的处理一致（PROJECT_SPEC 第二十节、docs/API.md 第 11 节）。

    带上有效 token 时每一项会多一个 `is_liked`。列表上就有爱心按钮，
    没有这个字段的话「我点过赞」在那里就画不出来 ——
    详情页是实心的、列表页是空心的，看起来像点赞没生效。
    """
    total = post_service.count_posts(db, category_id=category_id, keyword=keyword)
    items = post_service.list_posts(
        db,
        category_id=category_id,
        keyword=keyword,
        page=page,
        page_size=page_size,
    )
    liked = like_service.liked_post_ids(
        db, [item.id for item in items], user.id if user else None
    )

    return Page[PostItem](
        total=total,
        page=page,
        page_size=page_size,
        items=[
            PostItem.from_model(item, is_liked=item.id in liked) for item in items
        ],
    )


@router.get(
    "/{post_id}",
    response_model=PostDetail,
    summary="帖子详情",
    responses={404: {"description": "帖子不存在或已删除"}},
)
def get_post(
    post_id: int,
    user: User | None = Depends(get_optional_user),
    db: Session = Depends(get_db),
) -> PostDetail:
    """返回帖子全文。不需要登录；带了有效 token 会多一个 `is_liked`。

    详情页的评论列表是另一个接口（阶段 12b），
    本接口只返回 `comment_count` 这个计数。
    """
    item = post_service.get_post(db, post_id)
    if item is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="帖子不存在或已删除",
        )

    return PostDetail.from_model(
        item,
        is_liked=like_service.is_liked(db, post_id, user.id if user else None),
    )


@router.get(
    "/{post_id}/comments",
    response_model=Page[CommentItem],
    summary="评论列表",
    responses={404: {"description": "帖子不存在或已删除"}},
)
def list_comments(
    post_id: int,
    page: int = Query(1, ge=1, description="页码"),
    page_size: int = Query(20, ge=1, le=100, description="每页条数"),
    db: Session = Depends(get_db),
) -> Page[CommentItem]:
    """按时间正序返回评论。不需要登录。"""
    if post_service.get_post(db, post_id) is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="帖子不存在或已删除",
        )

    total = comment_service.count_comments(db, post_id)
    items = comment_service.list_comments(
        db, post_id, page=page, page_size=page_size
    )

    return Page[CommentItem](
        total=total,
        page=page,
        page_size=page_size,
        items=[CommentItem.from_model(item) for item in items],
    )


@router.post(
    "/{post_id}/comments",
    response_model=CommentItem,
    status_code=status.HTTP_201_CREATED,
    summary="发表评论",
    responses={
        401: {"description": "请先登录"},
        404: {"description": "帖子不存在或已删除"},
    },
)
def create_comment(
    post_id: int,
    payload: CommentCreate,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> CommentItem:
    """发表评论，需要登录。同时把帖子的评论数加一。"""
    post = post_service.get_post(db, post_id)
    if post is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="帖子不存在或已删除",
        )

    comment = comment_service.create_comment(
        db, post, user_id=user.id, content=payload.content
    )
    return CommentItem.from_model(comment)


def _find_post_or_404(db: Session, post_id: int):
    post = post_service.get_post(db, post_id)
    if post is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="帖子不存在或已删除",
        )
    return post


@router.post(
    "/{post_id}/like",
    response_model=LikeState,
    status_code=status.HTTP_201_CREATED,
    summary="点赞",
    responses={
        200: {"description": "之前已点过，返回当前状态（幂等）"},
        401: {"description": "请先登录"},
        404: {"description": "帖子不存在或已删除"},
    },
)
def like_post(
    post_id: int,
    response: Response,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> LikeState:
    """点赞。**幂等**：重复点赞不报错，也不会多出一个赞。

    新建时是 `201`，之前就点过时是 `200`。
    """
    post = _find_post_or_404(db, post_id)
    created, count = like_service.like(db, post, user_id=user.id)

    if not created:
        response.status_code = status.HTTP_200_OK

    return LikeState(like_count=count, is_liked=True)


@router.delete(
    "/{post_id}/like",
    response_model=LikeState,
    status_code=status.HTTP_200_OK,
    summary="取消点赞",
    responses={
        401: {"description": "请先登录"},
        404: {"description": "帖子不存在或已删除"},
    },
)
def unlike_post(
    post_id: int,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> LikeState:
    """取消点赞。**幂等**：本来就没点过也返回成功。

    与收藏 / 历史的 `DELETE` 不同，这里**返回 `200` 与响应体**而不是
    `204`。原因是点赞数就在按钮旁边显示，客户端需要拿到新的数字；
    让它自己减一的话，别人同时点赞时会越减越错。
    """
    post = _find_post_or_404(db, post_id)
    _, count = like_service.unlike(db, post, user_id=user.id)

    return LikeState(like_count=count, is_liked=False)
