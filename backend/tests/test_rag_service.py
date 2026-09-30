"""阶段 14：知识检索。

检索结果会被拼进提示词，并以「相关知识」的形式展示给用户 ——
它等同于对外宣称「这条内容与你的问题有关」，因此两条底线必须守住：

1. **未发布的卡片永远检索不到**。知识库的流程是「AI 生成初稿 → 人工审核 →
   发布」（PROJECT_SPEC 第十五节），把一篇还没审过的初稿当作引用来源
   递给用户，等于绕过了整条审核链。
2. **擦到一两个词不算相关**。引用一条明显不搭边的卡片，用户会以为
   这条回答是从那篇内容里来的。
"""

from __future__ import annotations

from sqlalchemy.orm import Session

from app.services.ai.rag_service import MAX_LIMIT, RAGService, _tokens
from tests.factories import create_knowledge, prepare_categories

FIRE_QUESTION = "宿舍发生火灾怎么办"


def _retrieve(db: Session, question: str = FIRE_QUESTION, **kwargs):
    return RAGService().retrieve(db, question, **kwargs)


class TestPublishedOnly:
    def test_unpublished_draft_is_never_retrieved(self, db_session: Session) -> None:
        prepare_categories(db_session)
        create_knowledge(
            db_session,
            title="宿舍火灾逃生要点",
            content="宿舍发生火灾怎么办：先叫醒室友，低姿撤离。",
            is_published=False,
        )

        assert _retrieve(db_session) == []

    def test_published_card_is_retrieved(self, db_session: Session) -> None:
        prepare_categories(db_session)
        card = create_knowledge(
            db_session,
            title="宿舍火灾逃生要点",
            content="宿舍发生火灾怎么办：先叫醒室友，低姿撤离。",
            is_published=True,
        )

        assert [item.id for item in _retrieve(db_session)] == [card.id]

    def test_a_draft_does_not_shadow_its_published_copy(self, db_session: Session) -> None:
        prepare_categories(db_session)
        create_knowledge(
            db_session,
            title="宿舍火灾逃生要点（初稿）",
            content="宿舍发生火灾怎么办",
            is_published=False,
        )
        published = create_knowledge(
            db_session,
            title="宿舍火灾逃生要点",
            content="宿舍发生火灾怎么办",
            is_published=True,
        )

        assert [item.id for item in _retrieve(db_session)] == [published.id]


class TestRelevance:
    def test_irrelevant_question_returns_nothing(self, db_session: Session) -> None:
        prepare_categories(db_session)
        create_knowledge(
            db_session,
            title="宿舍火灾逃生要点",
            content="低姿撤离，不要返回火场取物。",
            is_published=True,
        )

        assert _retrieve(db_session, "银行卡怎么提额") == []

    def test_title_match_outranks_content_match(self, db_session: Session) -> None:
        prepare_categories(db_session)
        by_title = create_knowledge(
            db_session,
            title="宿舍火灾逃生要点",
            content="低姿撤离。",
            is_published=True,
        )
        by_content = create_knowledge(
            db_session,
            title="消防常识",
            content="有人问宿舍发生火灾怎么办，答案永远是先撤离再报警。",
            is_published=True,
        )

        assert [item.id for item in _retrieve(db_session)] == [by_title.id, by_content.id]

    def test_a_stray_word_in_the_body_is_not_enough(self, db_session: Session) -> None:
        prepare_categories(db_session)
        create_knowledge(
            db_session,
            title="消防常识",
            content="发生火灾时要保持冷静，不要围观。",
            is_published=True,
        )

        assert _retrieve(db_session) == []

    def test_ascii_keywords_are_matched(self, db_session: Session) -> None:
        prepare_categories(db_session)
        card = create_knowledge(
            db_session,
            title="CPR 心肺复苏要点",
            content="按压深度与频率。",
            is_published=True,
        )

        assert [item.id for item in _retrieve(db_session, "cpr 怎么做")] == [card.id]

    def test_blank_question_returns_nothing(self, db_session: Session) -> None:
        prepare_categories(db_session)
        create_knowledge(
            db_session,
            title="宿舍火灾逃生要点",
            content="低姿撤离。",
            is_published=True,
        )

        assert _retrieve(db_session, "   ") == []
        assert _retrieve(db_session, "？！") == []

    def test_empty_library_returns_nothing(self, db_session: Session) -> None:
        prepare_categories(db_session)

        assert _retrieve(db_session) == []


class TestLimits:
    def test_result_count_is_capped_by_limit(self, db_session: Session) -> None:
        prepare_categories(db_session)
        for index in range(5):
            create_knowledge(
                db_session,
                title=f"宿舍火灾逃生要点 {index}",
                content="低姿撤离。",
                is_published=True,
            )

        assert len(_retrieve(db_session, limit=2)) == 2

    def test_limit_is_clamped_to_the_maximum(self, db_session: Session) -> None:
        prepare_categories(db_session)
        for index in range(MAX_LIMIT + 2):
            create_knowledge(
                db_session,
                title=f"宿舍火灾逃生要点 {index}",
                content="低姿撤离。",
                is_published=True,
            )

        assert len(_retrieve(db_session, limit=99)) == MAX_LIMIT

    def test_zero_limit_returns_nothing(self, db_session: Session) -> None:
        prepare_categories(db_session)
        create_knowledge(
            db_session,
            title="宿舍火灾逃生要点",
            content="低姿撤离。",
            is_published=True,
        )

        assert _retrieve(db_session, limit=0) == []


class TestPayload:
    def test_card_fields_are_carried_through(self, db_session: Session) -> None:
        prepare_categories(db_session)
        create_knowledge(
            db_session,
            title="宿舍火灾逃生要点",
            summary="低姿撤离，不要返回火场。",
            content="低姿撤离。",
            risk_level="high",
            source="《消防法》",
            is_published=True,
        )

        card = _retrieve(db_session)[0]

        assert card.title == "宿舍火灾逃生要点"
        assert card.summary == "低姿撤离，不要返回火场。"
        assert card.category_id == 1
        assert card.risk_level == "high"
        assert card.source == "《消防法》"

    def test_missing_summary_becomes_an_empty_string(self, db_session: Session) -> None:
        prepare_categories(db_session)
        create_knowledge(
            db_session,
            title="宿舍火灾逃生要点",
            summary=None,
            content="低姿撤离。",
            is_published=True,
        )

        assert _retrieve(db_session)[0].summary == ""


class TestTokens:
    def test_chinese_is_split_into_bigrams(self) -> None:
        assert _tokens("火灾") == {"火灾"}
        assert _tokens("宿舍火灾") == {"宿舍", "舍火", "火灾"}

    def test_ascii_is_split_into_words(self) -> None:
        assert _tokens("CPR 与 AED") == {"cpr", "aed", "与"}

    def test_blank_input_yields_nothing(self) -> None:
        assert _tokens(None) == set()
        assert _tokens("   ") == set()
