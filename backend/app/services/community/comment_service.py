"""评论业务逻辑。对应 docs/API.md 第 7 节。"""

from __future__ import annotations

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.models.comment import Comment
from app.models.post import Post

MIN_LENGTH = 1
MAX_LENGTH = 500


def normalize(content: str) -> str:
    return content.strip()


def count_comments(db: Session, post_id: int) -> int:
    return db.scalar(
        select(func.count()).select_from(Comment).where(Comment.post_id == post_id)
    ) or 0


def list_comments(
    db: Session,
    post_id: int,
    *,
    page: int = 1,
    page_size: int = 20,
) -> list[Comment]:
    stmt = (
        select(Comment)
        .where(Comment.post_id == post_id)
        .order_by(Comment.created_at.asc(), Comment.id.asc())
        .offset((page - 1) * page_size)
        .limit(page_size)
    )
    return list(db.scalars(stmt).unique().all())


def create_comment(
    db: Session,
    post: Post,
    *,
    user_id: int,
    content: str,
) -> Comment:
    comment = Comment(post_id=post.id, user_id=user_id, content=normalize(content))
    db.add(comment)
    db.flush()
    post.comment_count = count_comments(db, post.id)
    db.commit()
    db.refresh(comment)
    return comment
