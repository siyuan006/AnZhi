"""点赞业务逻辑。对应 docs/API.md 第 7 节。"""

from __future__ import annotations

from collections.abc import Sequence

from sqlalchemy import delete, func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.models.like import Like
from app.models.post import Post


def count_likes(db: Session, post_id: int) -> int:
    return db.scalar(
        select(func.count()).select_from(Like).where(Like.post_id == post_id)
    ) or 0


def liked_post_ids(
    db: Session, post_ids: Sequence[int], user_id: int | None
) -> set[int]:
    """一次查出「这批帖子里我点过赞的那些」。列表页用。

    逐条调用 `is_liked` 会变成 N+1 次查询：一页 20 条就是 20 次往返。
    """
    if user_id is None or not post_ids:
        return set()
    return set(
        db.scalars(
            select(Like.post_id).where(
                Like.user_id == user_id, Like.post_id.in_(post_ids)
            )
        )
    )


def is_liked(db: Session, post_id: int, user_id: int | None) -> bool:
    if user_id is None:
        return False
    return (
        db.scalar(
            select(Like.id)
            .where(Like.post_id == post_id, Like.user_id == user_id)
            .limit(1)
        )
        is not None
    )


def _sync_count(db: Session, post: Post) -> int:
    db.flush()
    post.like_count = count_likes(db, post.id)
    db.commit()
    return post.like_count


def like(db: Session, post: Post, *, user_id: int) -> tuple[bool, int]:
    """点赞。返回 `(这次是否真的新增了, 当前点赞数)`。

    重复点赞不报错，也不会多出一行 —— 数据库上有
    `UNIQUE(post_id, user_id)` 兜底，这里用一个保存点接住并发下
    可能出现的唯一约束冲突，而不是让请求变成 500。
    """
    if is_liked(db, post.id, user_id):
        return False, post.like_count

    try:
        with db.begin_nested():
            db.add(Like(post_id=post.id, user_id=user_id))
    except IntegrityError:
        return False, post.like_count

    return True, _sync_count(db, post)


def unlike(db: Session, post: Post, *, user_id: int) -> tuple[bool, int]:
    """取消点赞。同样幂等：本来就没点过也返回成功。"""
    removed = db.execute(
        delete(Like).where(Like.post_id == post.id, Like.user_id == user_id)
    ).rowcount

    return bool(removed), _sync_count(db, post)
