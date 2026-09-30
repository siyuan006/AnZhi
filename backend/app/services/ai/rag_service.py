from __future__ import annotations

import logging
import re
from dataclasses import dataclass

from sqlalchemy import select
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from app.models.knowledge import Knowledge

logger = logging.getLogger("anzhi")

DEFAULT_LIMIT = 3
MAX_LIMIT = 5
MAX_CANDIDATES = 300
MIN_SCORE = 1.0

TITLE_WEIGHT = 6
SUMMARY_WEIGHT = 3
CONTENT_WEIGHT = 1

_CJK_RUN = re.compile(r"[一-鿿]+")
_ASCII_WORD = re.compile(r"[a-z0-9]+")


@dataclass(frozen=True)
class RetrievedCard:
    id: int
    title: str
    summary: str
    category_id: int
    risk_level: str
    source: str | None
    score: float


def _tokens(text: str | None) -> set[str]:
    lowered = (text or "").lower()
    tokens: set[str] = set()

    for run in _CJK_RUN.findall(lowered):
        if len(run) == 1:
            tokens.add(run)
            continue
        tokens.update(run[index : index + 2] for index in range(len(run) - 1))

    tokens.update(_ASCII_WORD.findall(lowered))
    return tokens


def _score(question_tokens: set[str], card: Knowledge) -> float:
    weighted = (
        TITLE_WEIGHT * len(question_tokens & _tokens(card.title))
        + SUMMARY_WEIGHT * len(question_tokens & _tokens(card.summary))
        + CONTENT_WEIGHT * len(question_tokens & _tokens(card.content))
    )
    return weighted / len(question_tokens)


class RAGService:
    def retrieve(
        self,
        db: Session,
        question: str,
        limit: int = DEFAULT_LIMIT,
    ) -> list[RetrievedCard]:
        question_tokens = _tokens(question)
        if not question_tokens or limit < 1:
            return []

        try:
            candidates = self._published(db)
        except SQLAlchemyError as exc:
            logger.warning("知识检索失败，本次问答不带引用：%s", exc)
            return []

        scored = [(_score(question_tokens, card), card) for card in candidates]
        scored = [item for item in scored if item[0] >= MIN_SCORE]
        scored.sort(key=lambda item: item[0], reverse=True)

        return [
            RetrievedCard(
                id=card.id,
                title=card.title,
                summary=card.summary or "",
                category_id=card.category_id,
                risk_level=card.risk_level,
                source=card.source,
                score=score,
            )
            for score, card in scored[: min(limit, MAX_LIMIT)]
        ]

    @staticmethod
    def _published(db: Session) -> list[Knowledge]:
        stmt = (
            select(Knowledge)
            .where(Knowledge.is_published.is_(True))
            .order_by(Knowledge.created_at.desc(), Knowledge.id.desc())
            .limit(MAX_CANDIDATES)
        )
        return list(db.scalars(stmt).unique().all())
