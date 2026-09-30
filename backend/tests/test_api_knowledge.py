"""阶段 7：知识系统接口。

重点验证「未发布内容绝不外泄」—— 这是内容审核流程能否成立的关键。
"""

from __future__ import annotations

from fastapi.testclient import TestClient
from sqlalchemy.orm import Session, sessionmaker

from tests.factories import create_knowledge, prepare_categories


def _seed(session_factory: sessionmaker[Session]) -> None:
    """预置一批知识卡片：3 篇已发布、1 篇未发布。"""
    with session_factory() as db:
        prepare_categories(db)

        create_knowledge(
            db,
            title="宿舍消防安全",
            category_id=1,
            summary="宿舍常见火灾隐患与预防措施",
            risk_level="medium",
            is_published=True,
            content="宿舍内禁止使用大功率电器……",
            source="应急管理部",
            author="安知编辑部",
        )
        create_knowledge(
            db,
            title="灭火器的种类与选用",
            category_id=1,
            summary="干粉、二氧化碳、水基灭火器的区别",
            risk_level="low",
            is_published=True,
        )
        create_knowledge(
            db,
            title="电动车充电安全",
            category_id=2,
            summary="楼道充电的危险性",
            risk_level="high",
            is_published=True,
        )
        # 这篇是「AI 初稿，尚未人工审核」，任何接口都不应该返回它
        create_knowledge(
            db,
            title="尚未审核的草稿",
            category_id=1,
            summary="草稿摘要",
            is_published=False,
        )


class TestCategories:
    """GET /api/categories"""

    def test_returns_six_categories_in_order(
        self, api_client: TestClient, session_factory: sessionmaker[Session]
    ) -> None:
        with session_factory() as db:
            prepare_categories(db)

        response = api_client.get("/api/categories")
        assert response.status_code == 200

        body = response.json()
        assert [item["id"] for item in body] == [1, 2, 3, 4, 5, 6]
        assert [item["slug"] for item in body] == [
            "fire",
            "electric",
            "traffic",
            "campus",
            "cyber",
            "disaster",
        ]

    def test_includes_display_fields(
        self, api_client: TestClient, session_factory: sessionmaker[Session]
    ) -> None:
        with session_factory() as db:
            prepare_categories(db)

        first = api_client.get("/api/categories").json()[0]
        assert first["name"] == "消防安全"
        assert first["color"] == "#E53935"
        assert first["description"]

    def test_empty_database_returns_empty_list(self, api_client: TestClient) -> None:
        assert api_client.get("/api/categories").json() == []


class TestKnowledgeList:
    """GET /api/knowledge"""

    def test_only_published_items_are_returned(
        self, api_client: TestClient, session_factory: sessionmaker[Session]
    ) -> None:
        """未发布的草稿不得出现在列表里，也不得计入 total。"""
        _seed(session_factory)

        body = api_client.get("/api/knowledge").json()
        assert body["total"] == 3

        titles = [item["title"] for item in body["items"]]
        assert "尚未审核的草稿" not in titles

    def test_list_item_has_category_name(
        self, api_client: TestClient, session_factory: sessionmaker[Session]
    ) -> None:
        _seed(session_factory)

        items = api_client.get("/api/knowledge").json()["items"]
        by_title = {item["title"]: item for item in items}
        assert by_title["宿舍消防安全"]["category_name"] == "消防安全"

    def test_list_item_omits_content(
        self, api_client: TestClient, session_factory: sessionmaker[Session]
    ) -> None:
        """列表不返回正文，避免一页拖下 20 篇全文。"""
        _seed(session_factory)

        items = api_client.get("/api/knowledge").json()["items"]
        assert all("content" not in item for item in items)

    def test_filter_by_category(
        self, api_client: TestClient, session_factory: sessionmaker[Session]
    ) -> None:
        _seed(session_factory)

        body = api_client.get("/api/knowledge", params={"category_id": 1}).json()
        assert body["total"] == 2
        assert all(item["category_id"] == 1 for item in body["items"])

    def test_filter_by_risk_level(
        self, api_client: TestClient, session_factory: sessionmaker[Session]
    ) -> None:
        _seed(session_factory)

        body = api_client.get("/api/knowledge", params={"risk_level": "high"}).json()
        assert body["total"] == 1
        assert body["items"][0]["risk_level"] == "high"

    def test_invalid_risk_level_is_rejected(self, api_client: TestClient) -> None:
        """非法等级直接 422，而不是悄悄返回空列表。"""
        response = api_client.get("/api/knowledge", params={"risk_level": "HIGH"})
        assert response.status_code == 422
        assert "detail" in response.json()

    def test_keyword_matches_title(
        self, api_client: TestClient, session_factory: sessionmaker[Session]
    ) -> None:
        _seed(session_factory)

        body = api_client.get("/api/knowledge", params={"keyword": "灭火器"}).json()
        assert body["total"] == 1
        assert body["items"][0]["title"] == "灭火器的种类与选用"

    def test_keyword_matches_summary(
        self, api_client: TestClient, session_factory: sessionmaker[Session]
    ) -> None:
        _seed(session_factory)

        body = api_client.get("/api/knowledge", params={"keyword": "楼道"}).json()
        assert body["total"] == 1
        assert body["items"][0]["title"] == "电动车充电安全"

    def test_keyword_with_no_match_returns_empty_page(
        self, api_client: TestClient, session_factory: sessionmaker[Session]
    ) -> None:
        _seed(session_factory)

        body = api_client.get("/api/knowledge", params={"keyword": "不存在的词"}).json()
        assert body["total"] == 0
        assert body["items"] == []

    def test_pagination_keeps_total_and_slices_items(
        self, api_client: TestClient, session_factory: sessionmaker[Session]
    ) -> None:
        _seed(session_factory)

        first = api_client.get(
            "/api/knowledge", params={"page": 1, "page_size": 2}
        ).json()
        second = api_client.get(
            "/api/knowledge", params={"page": 2, "page_size": 2}
        ).json()

        # total 是符合条件的总数，不随分页变化
        assert first["total"] == second["total"] == 3
        assert len(first["items"]) == 2
        assert len(second["items"]) == 1

        # 两页不重复
        first_ids = {item["id"] for item in first["items"]}
        second_ids = {item["id"] for item in second["items"]}
        assert not (first_ids & second_ids)

    def test_page_size_upper_bound(self, api_client: TestClient) -> None:
        """page_size 上限 100，防止一次拉爆数据库。"""
        assert api_client.get("/api/knowledge", params={"page_size": 101}).status_code == 422

    def test_page_must_be_positive(self, api_client: TestClient) -> None:
        assert api_client.get("/api/knowledge", params={"page": 0}).status_code == 422

    def test_newest_first(
        self, api_client: TestClient, session_factory: sessionmaker[Session]
    ) -> None:
        _seed(session_factory)

        items = api_client.get("/api/knowledge").json()["items"]
        created = [item["created_at"] for item in items]
        assert created == sorted(created, reverse=True)

    def test_empty_database_returns_empty_page(self, api_client: TestClient) -> None:
        body = api_client.get("/api/knowledge").json()
        assert body == {"total": 0, "page": 1, "page_size": 20, "items": []}


class TestKnowledgeDetail:
    """GET /api/knowledge/{id}"""

    def test_returns_full_content(
        self, api_client: TestClient, session_factory: sessionmaker[Session]
    ) -> None:
        _seed(session_factory)

        listed = api_client.get("/api/knowledge").json()["items"]
        target = next(item for item in listed if item["title"] == "宿舍消防安全")

        body = api_client.get(f"/api/knowledge/{target['id']}").json()
        assert body["content"] == "宿舍内禁止使用大功率电器……"
        assert body["source"] == "应急管理部"
        assert body["author"] == "安知编辑部"
        assert body["category_name"] == "消防安全"

    def test_unpublished_returns_404(
        self, api_client: TestClient, session_factory: sessionmaker[Session]
    ) -> None:
        """未发布内容对外一律视为不存在，不返回 403。

        返回 403 等于告诉外部「这里有一篇还没审核的内容」。
        """
        with session_factory() as db:
            prepare_categories(db)
            draft = create_knowledge(db, title="草稿", is_published=False)
            draft_id = draft.id

        response = api_client.get(f"/api/knowledge/{draft_id}")
        assert response.status_code == 404
        assert response.json()["detail"] == "知识不存在或未发布"

    def test_missing_id_returns_404(self, api_client: TestClient) -> None:
        assert api_client.get("/api/knowledge/9999").status_code == 404

    def test_non_integer_id_returns_422(self, api_client: TestClient) -> None:
        assert api_client.get("/api/knowledge/abc").status_code == 422
