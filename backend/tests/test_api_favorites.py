"""收藏接口的测试（docs/API.md 第 5 节）。

除了正常的收藏 / 取消 / 列表，重点守四件事：

 · **越权**：A 不能读到、也不能删掉 B 的收藏
 · **未发布内容不外泄**：收藏一个未发布的 id 必须和不存在一样返回 404
 · **幂等**：重复收藏、重复取消都不报错
 · **撤下的内容不出现在列表里**：收藏过不等于永远看得到

前两条挂了是安全事故，后两条挂了只是体验问题 —— 但都会让
「我的收藏」这个功能失去可信度。
"""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import func, select
from sqlalchemy.orm import Session, sessionmaker

from app.models.favorite import Favorite
from app.models.knowledge import Knowledge
from tests.factories import create_knowledge, prepare_categories

FAVORITES = "/api/favorites"

GOOD_PASSWORD = "hunter2hunter2"


def register(client: TestClient, username: str) -> str:
    """注册一个账号并返回它的 token。"""
    response = client.post(
        "/api/auth/register",
        json={"username": username, "password": GOOD_PASSWORD},
    )
    assert response.status_code == 201, response.text
    return response.json()["access_token"]


def auth_header(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture
def token(api_client: TestClient) -> str:
    return register(api_client, "alice")


@pytest.fixture
def published(session_factory: sessionmaker[Session]) -> int:
    """一篇已发布的知识，返回它的 id。"""
    with session_factory() as db:
        prepare_categories(db)
        item = create_knowledge(db, is_published=True)
        return item.id


def favorite_count(session_factory: sessionmaker[Session]) -> int:
    with session_factory() as db:
        return db.scalar(select(func.count()).select_from(Favorite)) or 0


class TestAuthIsRequired:
    """收藏是「这份数据属于谁」的问题，是少数真的需要问「你是谁」的地方。"""

    def test_listing_without_a_token_is_a_401(self, api_client: TestClient):
        response = api_client.get(FAVORITES)

        assert response.status_code == 401
        assert response.json()["detail"] == "请先登录"

    def test_adding_without_a_token_is_a_401(
        self, api_client: TestClient, published: int
    ):
        response = api_client.post(FAVORITES, json={"knowledge_id": published})

        assert response.status_code == 401

    def test_removing_without_a_token_is_a_401(
        self, api_client: TestClient, published: int
    ):
        response = api_client.delete(f"{FAVORITES}/{published}")

        assert response.status_code == 401


class TestAddFavorite:
    def test_creates_and_returns_the_record(
        self, api_client: TestClient, token: str, published: int
    ):
        response = api_client.post(
            FAVORITES, json={"knowledge_id": published}, headers=auth_header(token)
        )

        assert response.status_code == 201
        body = response.json()
        assert body["id"] > 0
        assert body["knowledge_id"] == published
        assert body["created_at"]

    def test_adding_twice_is_idempotent(
        self,
        api_client: TestClient,
        token: str,
        published: int,
        session_factory: sessionmaker[Session],
    ):
        """重复收藏返回同一条记录，数据库里也只有一行。

        收藏按钮是个开关。用户连点两下、或者网络慢时客户端自动重试，
        都不该弹出红色错误提示 —— 那是为一件已经达成的事报错。
        """
        first = api_client.post(
            FAVORITES, json={"knowledge_id": published}, headers=auth_header(token)
        )
        second = api_client.post(
            FAVORITES, json={"knowledge_id": published}, headers=auth_header(token)
        )

        assert second.status_code == 200, "已收藏过用 200，如实区分「这次没新建」"
        assert second.json()["id"] == first.json()["id"]
        assert favorite_count(session_factory) == 1

    def test_unknown_knowledge_is_a_404(self, api_client: TestClient, token: str):
        response = api_client.post(
            FAVORITES, json={"knowledge_id": 999999}, headers=auth_header(token)
        )

        assert response.status_code == 404
        assert response.json()["detail"] == "知识不存在或未发布"

    def test_unpublished_knowledge_is_a_404(
        self,
        api_client: TestClient,
        token: str,
        session_factory: sessionmaker[Session],
    ):
        """未发布的知识必须和不存在**完全一样**。

        若这里返回 403 或一句「该内容未发布」，等于对外确认了
        「这个 id 上有一篇还没审核的内容」。
        """
        with session_factory() as db:
            prepare_categories(db)
            hidden = create_knowledge(db, is_published=False)
            hidden_id = hidden.id

        response = api_client.post(
            FAVORITES, json={"knowledge_id": hidden_id}, headers=auth_header(token)
        )
        missing = api_client.post(
            FAVORITES, json={"knowledge_id": 999999}, headers=auth_header(token)
        )

        assert response.status_code == 404
        assert response.json() == missing.json()

    def test_nothing_is_written_when_the_knowledge_is_invisible(
        self,
        api_client: TestClient,
        token: str,
        session_factory: sessionmaker[Session],
    ):
        """404 之后数据库里不能留下半条记录。"""
        with session_factory() as db:
            prepare_categories(db)
            hidden_id = create_knowledge(db, is_published=False).id

        api_client.post(
            FAVORITES, json={"knowledge_id": hidden_id}, headers=auth_header(token)
        )

        assert favorite_count(session_factory) == 0

    def test_rejects_a_missing_knowledge_id(self, api_client: TestClient, token: str):
        response = api_client.post(FAVORITES, json={}, headers=auth_header(token))

        assert response.status_code == 422


class TestRemoveFavorite:
    def test_removes_the_record(
        self,
        api_client: TestClient,
        token: str,
        published: int,
        session_factory: sessionmaker[Session],
    ):
        api_client.post(
            FAVORITES, json={"knowledge_id": published}, headers=auth_header(token)
        )

        response = api_client.delete(
            f"{FAVORITES}/{published}", headers=auth_header(token)
        )

        assert response.status_code == 204
        assert response.content == b""
        assert favorite_count(session_factory) == 0

    def test_removing_something_never_favorited_is_still_a_204(
        self, api_client: TestClient, token: str, published: int
    ):
        """幂等：用户要的是「这条不在我的收藏里」，而这个状态已经成立。"""
        response = api_client.delete(
            f"{FAVORITES}/{published}", headers=auth_header(token)
        )

        assert response.status_code == 204

    def test_removing_twice_is_still_a_204(
        self, api_client: TestClient, token: str, published: int
    ):
        api_client.post(
            FAVORITES, json={"knowledge_id": published}, headers=auth_header(token)
        )

        first = api_client.delete(
            f"{FAVORITES}/{published}", headers=auth_header(token)
        )
        second = api_client.delete(
            f"{FAVORITES}/{published}", headers=auth_header(token)
        )

        assert first.status_code == second.status_code == 204


class TestIsolationBetweenUsers:
    """一个用户绝不能碰到另一个用户的收藏。

    这一组挂了就是越权漏洞，不是体验问题。
    """

    def test_a_user_cannot_delete_another_users_favorite(
        self,
        api_client: TestClient,
        token: str,
        published: int,
        session_factory: sessionmaker[Session],
    ):
        api_client.post(
            FAVORITES, json={"knowledge_id": published}, headers=auth_header(token)
        )
        mallory = register(api_client, "mallory")

        # mallory 猜到了 knowledge_id，直接来删
        response = api_client.delete(
            f"{FAVORITES}/{published}", headers=auth_header(mallory)
        )

        # 204 是幂等的正常返回（对 mallory 来说他本来就没有这条收藏），
        # 但**数据必须还在** —— 这才是这条测试真正守的东西
        assert response.status_code == 204
        assert favorite_count(session_factory) == 1

    def test_a_user_cannot_see_another_users_favorites(
        self,
        api_client: TestClient,
        token: str,
        published: int,
    ):
        api_client.post(
            FAVORITES, json={"knowledge_id": published}, headers=auth_header(token)
        )
        mallory = register(api_client, "mallory")

        body = api_client.get(FAVORITES, headers=auth_header(mallory)).json()

        assert body["total"] == 0
        assert body["items"] == []

    def test_detail_page_does_not_report_another_users_favorite(
        self,
        api_client: TestClient,
        token: str,
        published: int,
    ):
        """详情页的收藏按钮状态也必须按人算。

        直接查「这条知识有没有被任何人收藏」是最容易写错的一版 ——
        它会让 B 打开 A 收藏过的文章时看到一个已点亮的收藏按钮。
        """
        api_client.post(
            FAVORITES, json={"knowledge_id": published}, headers=auth_header(token)
        )
        mallory = register(api_client, "mallory")

        body = api_client.get(
            f"/api/knowledge/{published}", headers=auth_header(mallory)
        ).json()

        assert body["is_favorited"] is False


class TestListFavorites:
    def test_returns_the_favorited_knowledge(
        self, api_client: TestClient, token: str, published: int
    ):
        api_client.post(
            FAVORITES, json={"knowledge_id": published}, headers=auth_header(token)
        )

        body = api_client.get(FAVORITES, headers=auth_header(token)).json()

        assert body["total"] == 1
        item = body["items"][0]
        assert item["knowledge_id"] == published
        # 列表要能直接渲染标题和分类，否则客户端得逐条再查一次详情
        assert item["knowledge"]["id"] == published
        assert item["knowledge"]["title"]
        assert item["knowledge"]["category_name"] != "未分类"

    def test_is_empty_before_anything_is_favorited(
        self, api_client: TestClient, token: str
    ):
        body = api_client.get(FAVORITES, headers=auth_header(token)).json()

        assert body == {"total": 0, "page": 1, "page_size": 20, "items": []}

    def test_most_recently_favorited_comes_first(
        self,
        api_client: TestClient,
        token: str,
        session_factory: sessionmaker[Session],
    ):
        with session_factory() as db:
            prepare_categories(db)
            first = create_knowledge(db, title="先收藏的", is_published=True).id
            second = create_knowledge(db, title="后收藏的", is_published=True).id

        api_client.post(
            FAVORITES, json={"knowledge_id": first}, headers=auth_header(token)
        )
        api_client.post(
            FAVORITES, json={"knowledge_id": second}, headers=auth_header(token)
        )

        body = api_client.get(FAVORITES, headers=auth_header(token)).json()

        assert [i["knowledge_id"] for i in body["items"]] == [second, first]

    def test_unpublished_knowledge_drops_out_of_the_list(
        self,
        api_client: TestClient,
        token: str,
        session_factory: sessionmaker[Session],
    ):
        """收藏之后内容被撤下审核，列表里不能留下一条点不开的入口。

        收藏记录仍在数据库里（重新发布后应该还能看到），
        但对外列表和 `total` 都要如实排除它。
        """
        with session_factory() as db:
            prepare_categories(db)
            item = create_knowledge(db, is_published=True)
            item_id = item.id

        api_client.post(
            FAVORITES, json={"knowledge_id": item_id}, headers=auth_header(token)
        )
        assert api_client.get(FAVORITES, headers=auth_header(token)).json()["total"] == 1

        with session_factory() as db:
            row = db.get(Knowledge, item_id)
            assert row is not None
            row.is_published = False
            db.commit()

        body = api_client.get(FAVORITES, headers=auth_header(token)).json()

        assert body["total"] == 0
        assert body["items"] == []
        # 记录本身还在 —— 重新发布后收藏应该回来
        assert favorite_count(session_factory) == 1

    def test_pagination_is_consistent_with_the_total(
        self,
        api_client: TestClient,
        token: str,
        session_factory: sessionmaker[Session],
    ):
        """总数与列表必须来自同一组筛选条件。

        两者各写一份 SQL 时，很容易出现「总数说有 5 条、列表只给 3 条」。
        """
        with session_factory() as db:
            prepare_categories(db)
            ids = [
                create_knowledge(db, title=f"第 {n} 篇", is_published=True).id
                for n in range(5)
            ]

        for knowledge_id in ids:
            api_client.post(
                FAVORITES,
                json={"knowledge_id": knowledge_id},
                headers=auth_header(token),
            )

        first = api_client.get(
            f"{FAVORITES}?page=1&page_size=2", headers=auth_header(token)
        ).json()
        last = api_client.get(
            f"{FAVORITES}?page=3&page_size=2", headers=auth_header(token)
        ).json()

        assert first["total"] == last["total"] == 5
        assert len(first["items"]) == 2
        assert len(last["items"]) == 1

    def test_page_size_is_capped(self, api_client: TestClient, token: str):
        response = api_client.get(
            f"{FAVORITES}?page_size=1000", headers=auth_header(token)
        )

        assert response.status_code == 422


class TestIsFavoritedOnTheDetailPage:
    def test_is_false_for_anonymous_readers(
        self, api_client: TestClient, published: int
    ):
        """不登录也能读详情 —— 顺带告诉他「未收藏」，但绝不能是 401。"""
        response = api_client.get(f"/api/knowledge/{published}")

        assert response.status_code == 200
        assert response.json()["is_favorited"] is False

    def test_becomes_true_after_favoriting(
        self, api_client: TestClient, token: str, published: int
    ):
        api_client.post(
            FAVORITES, json={"knowledge_id": published}, headers=auth_header(token)
        )

        body = api_client.get(
            f"/api/knowledge/{published}", headers=auth_header(token)
        ).json()

        assert body["is_favorited"] is True

    def test_becomes_false_again_after_removing(
        self, api_client: TestClient, token: str, published: int
    ):
        api_client.post(
            FAVORITES, json={"knowledge_id": published}, headers=auth_header(token)
        )
        api_client.delete(f"{FAVORITES}/{published}", headers=auth_header(token))

        body = api_client.get(
            f"/api/knowledge/{published}", headers=auth_header(token)
        ).json()

        assert body["is_favorited"] is False

    def test_reading_the_detail_has_no_side_effects(
        self,
        api_client: TestClient,
        token: str,
        published: int,
        session_factory: sessionmaker[Session],
    ):
        """详情仍是纯读接口：读一次不会顺手建一条收藏。"""
        api_client.get(f"/api/knowledge/{published}", headers=auth_header(token))

        assert favorite_count(session_factory) == 0


class TestFavoritesDoNotLeakPrivateData:
    def test_response_never_contains_a_password_hash(
        self, api_client: TestClient, token: str, published: int
    ):
        api_client.post(
            FAVORITES, json={"knowledge_id": published}, headers=auth_header(token)
        )

        raw = api_client.get(FAVORITES, headers=auth_header(token)).text

        assert "$2b$" not in raw
        assert "password" not in raw.lower()

    def test_list_does_not_expose_other_users_ids(
        self,
        api_client: TestClient,
        token: str,
        published: int,
        session_factory: sessionmaker[Session],
    ):
        """列表里的 `id` 是收藏记录的 id，不是用户的 id —— 别把 user_id 带出去。"""
        api_client.post(
            FAVORITES, json={"knowledge_id": published}, headers=auth_header(token)
        )

        item = api_client.get(FAVORITES, headers=auth_header(token)).json()["items"][0]

        assert "user_id" not in item
        assert "user" not in item
