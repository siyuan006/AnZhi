"""阶段 7：知识内容审核流程。

这些测试保证「AI 初稿 → 人工审核 → 发布」不是一句口号：
初稿导入后必须不可见，只有显式发布后才出现在接口返回里。
"""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import select
from sqlalchemy.orm import Session, sessionmaker

from app.database.knowledge_drafts import DRAFT_KNOWLEDGE
from app.database.review import import_drafts, list_items, parse_ids, set_published
from app.models import Knowledge
from tests.factories import prepare_categories


class TestDraftContent:
    """初稿本身的数据质量（不需要数据库）。"""

    def test_titles_are_unique(self) -> None:
        titles = [draft.title for draft in DRAFT_KNOWLEDGE]
        assert len(titles) == len(set(titles))

    def test_risk_levels_are_valid(self) -> None:
        assert all(draft.risk_level in {"low", "medium", "high"} for draft in DRAFT_KNOWLEDGE)

    def test_category_ids_cover_all_six(self) -> None:
        """六大分类都要有内容，否则前端会出现空分类。"""
        assert {draft.category_id for draft in DRAFT_KNOWLEDGE} == {1, 2, 3, 4, 5, 6}

    def test_text_fields_are_filled(self) -> None:
        for draft in DRAFT_KNOWLEDGE:
            assert draft.title.strip()
            assert draft.summary.strip()
            assert len(draft.content.strip()) > 50, f"{draft.title} 正文过短"

    def test_every_category_has_a_high_risk_item_or_not(self) -> None:
        """高风险条目必须覆盖到紧急场景，且不能只写一句了事。"""
        high = [draft for draft in DRAFT_KNOWLEDGE if draft.risk_level == "high"]
        assert len(high) >= 4
        assert all(len(draft.content) > 200 for draft in high)


class TestImportDrafts:
    """导入初稿。"""

    def test_imports_all_drafts_as_unpublished(self, db_session: Session) -> None:
        prepare_categories(db_session)

        assert import_drafts(db_session) == len(DRAFT_KNOWLEDGE)

        rows = db_session.scalars(select(Knowledge)).all()
        assert len(rows) == len(DRAFT_KNOWLEDGE)
        # 这是整个流程的关键：导入不等于发布
        assert all(row.is_published is False for row in rows)

    def test_import_is_idempotent(self, db_session: Session) -> None:
        prepare_categories(db_session)

        import_drafts(db_session)
        assert import_drafts(db_session) == 0

        assert len(db_session.scalars(select(Knowledge)).all()) == len(DRAFT_KNOWLEDGE)

    def test_import_preserves_risk_levels(self, db_session: Session) -> None:
        prepare_categories(db_session)
        import_drafts(db_session)

        stored = {row.title: row.risk_level for row in db_session.scalars(select(Knowledge))}
        for draft in DRAFT_KNOWLEDGE:
            assert stored[draft.title] == draft.risk_level


class TestPublishFlow:
    """发布 / 撤回。"""

    def _import(self, db_session: Session) -> list[Knowledge]:
        prepare_categories(db_session)
        import_drafts(db_session)
        return list(db_session.scalars(select(Knowledge).order_by(Knowledge.id)).all())

    def test_publish_changes_state(self, db_session: Session) -> None:
        items = self._import(db_session)
        target_ids = [items[0].id, items[1].id]

        assert set_published(db_session, target_ids, published=True) == 2

        for item in db_session.scalars(select(Knowledge).order_by(Knowledge.id)):
            assert item.is_published is (item.id in target_ids)

    def test_publishing_twice_reports_no_change(self, db_session: Session) -> None:
        """已发布的条目再次发布不应重复计数。"""
        items = self._import(db_session)

        assert set_published(db_session, [items[0].id], published=True) == 1
        assert set_published(db_session, [items[0].id], published=True) == 0

    def test_unpublish_after_publish(self, db_session: Session) -> None:
        items = self._import(db_session)

        set_published(db_session, [items[0].id], published=True)
        assert set_published(db_session, [items[0].id], published=False) == 1

        db_session.expire_all()
        row = db_session.scalar(select(Knowledge).where(Knowledge.id == items[0].id))
        assert row.is_published is False

    def test_unknown_id_is_skipped(self, db_session: Session) -> None:
        items = self._import(db_session)

        # 9999 不存在，但不应抛异常，也不影响其他 id 的处理
        assert set_published(db_session, [items[0].id, 9999], published=True) == 1


class TestParseIds:
    """命令行参数解析。"""

    def test_comma_separated(self, db_session: Session) -> None:
        assert parse_ids("1, 2 ,3", db_session) == [1, 2, 3]

    def test_all_returns_every_id(self, db_session: Session) -> None:
        prepare_categories(db_session)
        import_drafts(db_session)

        ids = parse_ids("all", db_session)
        assert len(ids) == len(DRAFT_KNOWLEDGE)
        assert ids == sorted(ids)

    def test_non_numeric_is_rejected(self, db_session: Session) -> None:
        with pytest.raises(ValueError):
            parse_ids("abc", db_session)


class TestReviewToApiIntegration:
    """端到端：审核发布后，接口才返回内容。

    这是把「审核流程」和「对外接口」连起来验证的一条测试 ——
    单独测导入、单独测接口，都无法发现两者之间的断层。
    """

    def test_published_content_becomes_visible(
        self,
        api_client: TestClient,
        session_factory: sessionmaker[Session],
    ) -> None:
        with session_factory() as db:
            prepare_categories(db)
            import_drafts(db)

        # 导入后：接口看不到任何内容
        assert api_client.get("/api/knowledge").json()["total"] == 0

        with session_factory() as db:
            ids = parse_ids("all", db)
            set_published(db, ids[:3], published=True)

        # 发布 3 条后：接口能看到这 3 条
        body = api_client.get("/api/knowledge").json()
        assert body["total"] == 3
        assert len(body["items"]) == 3

        # 详情接口也能取到正文
        detail = api_client.get(f"/api/knowledge/{body['items'][0]['id']}").json()
        assert len(detail["content"]) > 50

    def test_unpublishing_hides_content_again(
        self,
        api_client: TestClient,
        session_factory: sessionmaker[Session],
    ) -> None:
        with session_factory() as db:
            prepare_categories(db)
            import_drafts(db)
            ids = parse_ids("all", db)
            set_published(db, ids, published=True)

        assert api_client.get("/api/knowledge").json()["total"] == len(DRAFT_KNOWLEDGE)

        with session_factory() as db:
            set_published(db, ids[:5], published=False)

        assert api_client.get("/api/knowledge").json()["total"] == len(DRAFT_KNOWLEDGE) - 5


class TestListItems:
    """`--list` 的过滤行为。"""

    def test_only_unpublished_filter(self, db_session: Session, capsys) -> None:
        prepare_categories(db_session)
        import_drafts(db_session)
        first_id = db_session.scalars(select(Knowledge.id).order_by(Knowledge.id)).first()
        set_published(db_session, [first_id], published=True)

        total = list_items(db_session)
        assert total == len(DRAFT_KNOWLEDGE)

        pending = list_items(db_session, only_unpublished=True)
        assert pending == len(DRAFT_KNOWLEDGE) - 1

    def test_empty_database_prints_notice(self, db_session: Session, capsys) -> None:
        assert list_items(db_session) == 0
        assert "没有符合条件" in capsys.readouterr().out
