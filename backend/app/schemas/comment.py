"""评论相关数据结构。对应 docs/API.md 第 7 节。"""

from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, Field, field_validator

from app.models.comment import Comment
from app.schemas.post import PostAuthor
from app.services.community import comment_service


class CommentItem(BaseModel):
    id: int
    content: str
    author: PostAuthor
    created_at: datetime

    @classmethod
    def from_model(cls, row: Comment) -> "CommentItem":
        return cls(
            id=row.id,
            content=row.content,
            author=PostAuthor(id=row.author.id, name=row.author_name),
            created_at=row.created_at,
        )


class CommentCreate(BaseModel):
    content: str = Field(..., description="评论正文")

    @field_validator("content")
    @classmethod
    def check_length(cls, value: str) -> str:
        normalized = comment_service.normalize(value)
        if len(normalized) < comment_service.MIN_LENGTH:
            raise ValueError("评论内容不能为空")
        if len(normalized) > comment_service.MAX_LENGTH:
            raise ValueError(f"评论最长 {comment_service.MAX_LENGTH} 个字")
        return normalized
