"""浏览历史接口的测试（docs/API.md 第 6 节）。

除了正常的记录 / 列表 / 删除，重点守四件事：

 · **越权**：A 不能读到、也不能删掉 B 的历史；「清空」只清自己的
 · **未发布内容不外泄**：浏览一个未发布的 id 必须和不存在一样返回 404，
   而且不能留下任何历史行
 · **同一篇只留一条**：重复浏览刷新时间，不新增记录（docs/DATABASE.md 3.5）
 · **匿名浏览不写任何人的历史**：历史要挂在具体用户上，
   但匿名读知识本身必须照常可用

前两条挂了是安全事故，后两条挂了是「历史」这个功能失去可信度 ——
一个会把别人记录删掉、或者自己越看越多的历史列表，用户不会再打开第二次。
"""

from __future__ import annotations

from datetime import timedelta

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import func, select
from sqlalchemy.orm import Session, sessionmaker

from app.database.base import utcnow
from app.models.history import History
from app.models.knowledge import Knowledge
from tests.factories import create_knowledge, make_history, prepare_categories

HISTORY = "/api/history"

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


def view(client: TestClient, knowledge_id: int, token: str | None = None) -> None:
    """模拟客户端打开一次详情页。"""
    response = client.post(
        f"/api/knowledge/{knowledge_id}/view",
        headers=auth_header(token) if token else {},
    )
    assert response.status_code == 200, response.text


def history_count(session_factory: sessionmaker[Session]) -> int:
    with session_factory() as db:
        return db.scalar(select(func.count()).select_from(History)) or 0


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


class TestAuthIsRequired:
    """历史记录和收藏一样，是「这份数据属于谁」的问题。"""

    def test_listing_without_a_token_is_a_401(self, api_client: TestClient):
        response = api_client.get(HISTORY)

        assert response.status_code == 401
        assert response.json()["detail"] == "请先登录"

    def test_clearing_without_a_token_is_a_401(self, api_client: TestClient):
        response = api_client.delete(HISTORY)

        assert response.status_code == 401

    def test_removing_one_without_a_token_is_a_401(
        self, api_client: TestClient, published: int
    ):
        response = api_client.delete(f"{HISTORY}/{published}")

        assert response.status_code == 401


class TestRecording:
    """浏览历史是浏览知识时的副作用，挂在 POST /view 上。"""

    def test_viewing_while_logged_in_records_it(
        self, api_client: TestClient, token: str, published: int
    ):
        view(api_client, published, token)

        body = api_client.get(HISTORY, headers=auth_header(token)).json()
        assert body["total"] == 1
        assert body["items"][0]["knowledge_id"] == published

    def test_viewing_anonymously_records_nothing(
        self, api_client: TestClient, session_factory: sessionmaker[Session],
        published: int,
    ):
        """匿名浏览知识是允许的，只是没有「谁」可以记。

        这里同时验证两件事：请求**不是** 401（匿名读知识必须照常可用），
        以及数据库里没有多出任何一行 —— 不能因为「没人可记」
        就记到某个默认用户名下。
        """
        view(api_client, published, token=None)

        assert history_count(session_factory) == 0

    def test_viewing_twice_keeps_a_single_row(
        self, api_client: TestClient, session_factory: sessionmaker[Session],
        token: str, published: int,
    ):
        """同一用户反复浏览同一篇，只更新那条记录的时间。"""
        view(api_client, published, token)
        view(api_client, published, token)
        view(api_client, published, token)

        assert history_count(session_factory) == 1

        body = api_client.get(HISTORY, headers=auth_header(token)).json()
        assert body["total"] == 1
        assert len(body["items"]) == 1

    def test_viewing_again_refreshes_the_time(
        self, api_client: TestClient, session_factory: sessionmaker[Session],
        token: str, published: int,
    ):
        """「只保留一条」不能变成「只保留第一次的时间」——

        那样历史列表里躺着的永远是最早那次浏览的时刻，
        看起来就像之后再看都没生效。
        """
        long_ago = utcnow() - timedelta(days=3)
        with session_factory() as db:
            db.add(make_history(knowledge_id=published, viewed_at=long_ago))
            db.commit()

        view(api_client, published, token)

        with session_factory() as db:
            row = db.scalar(select(History).where(History.knowledge_id == published))
            assert row is not None
            assert row.viewed_at > long_ago

    def test_viewing_unpublished_records_nothing(
        self, api_client: TestClient, session_factory: sessionmaker[Session],
        token: str,
    ):
        """未发布内容对外一律视为不存在，浏览它同样是 404 且不留痕迹。

        留下历史行等于承认「这个 id 背后有一条内容」。
        """
        with session_factory() as db:
            prepare_categories(db)
            draft = create_knowledge(db, is_published=False)
            draft_id = draft.id

        response = api_client.post(
            f"/api/knowledge/{draft_id}/view", headers=auth_header(token)
        )

        assert response.status_code == 404
        assert history_count(session_factory) == 0

    def test_recording_does_not_disturb_the_view_count(
        self, api_client: TestClient, token: str, published: int
    ):
        """记历史是顺带的，不能把浏览量算错。"""
        view(api_client, published, token)
        view(api_client, published, token)

        detail = api_client.get(f"/api/knowledge/{published}").json()
        assert detail["view_count"] == 2


class TestListHistory:
    def test_is_empty_before_anything_is_viewed(
        self, api_client: TestClient, token: str
    ):
        body = api_client.get(HISTORY, headers=auth_header(token)).json()

        assert body == {"total": 0, "page": 1, "page_size": 20, "items": []}

    def test_newest_first(
        self, api_client: TestClient, session_factory: sessionmaker[Session],
        token: str,
    ):
        with session_factory() as db:
            prepare_categories(db)
            older = create_knowledge(db, title="先看的", is_published=True)
            newer = create_knowledge(db, title="后看的", is_published=True)
            db.add(
                make_history(
                    knowledge_id=older.id, viewed_at=utcnow() - timedelta(hours=2)
                )
            )
            db.add(make_history(knowledge_id=newer.id, viewed_at=utcnow()))
            db.commit()

        body = api_client.get(HISTORY, headers=auth_header(token)).json()

        assert [item["knowledge"]["title"] for item in body["items"]] == [
            "后看的",
            "先看的",
        ]

    def test_each_row_carries_the_knowledge(
        self, api_client: TestClient, token: str, published: int
    ):
        """只给 knowledge_id 的话，客户端渲染一页 20 条要再发 20 次请求。"""
        view(api_client, published, token)

        item = api_client.get(HISTORY, headers=auth_header(token)).json()["items"][0]

        assert item["knowledge"]["id"] == published
        assert item["knowledge"]["title"], "标题不能为空，字段名可能已漂移"
        assert item["knowledge"]["category_name"] != "未分类"
        # 列表项不带正文，历史列表同样不该带
        assert "content" not in item["knowledge"]

    def test_pagination_is_consistent_with_the_total(
        self, api_client: TestClient, session_factory: sessionmaker[Session],
        token: str,
    ):
        with session_factory() as db:
            prepare_categories(db)
            for index in range(5):
                item = create_knowledge(db, title=f"第 {index} 条", is_published=True)
                db.add(
                    make_history(
                        knowledge_id=item.id,
                        viewed_at=utcnow() - timedelta(minutes=index),
                    )
                )
            db.commit()

        first = api_client.get(
            f"{HISTORY}?page=1&page_size=2", headers=auth_header(token)
        ).json()
        last = api_client.get(
            f"{HISTORY}?page=3&page_size=2", headers=auth_header(token)
        ).json()

        assert first["total"] == last["total"] == 5
        assert len(first["items"]) == 2
        assert len(last["items"]) == 1

    def test_page_size_is_capped(
        self, api_client: TestClient, token: str
    ):
        response = api_client.get(
            f"{HISTORY}?page_size=1000", headers=auth_header(token)
        )

        assert response.status_code == 422

    def test_unpublished_knowledge_drops_out_of_the_list(
        self, api_client: TestClient, session_factory: sessionmaker[Session],
        token: str, published: int,
    ):
        """浏览过不等于永远看得到 —— 内容被撤回后要点不开的入口不该留着。

        记录本身还在数据库里，内容重新发布后会自然回到列表。
        """
        view(api_client, published, token)

        with session_factory() as db:
            item = db.get(Knowledge, published)
            assert item is not None
            item.is_published = False
            db.commit()

        body = api_client.get(HISTORY, headers=auth_header(token)).json()

        assert body["total"] == 0
        assert body["items"] == []
        # 记录还在 —— 只是这一条现在不可见
        assert history_count(session_factory) == 1


class TestRemovingHistory:
    def test_removing_one_leaves_the_rest(
        self, api_client: TestClient, session_factory: sessionmaker[Session],
        token: str,
    ):
        with session_factory() as db:
            prepare_categories(db)
            first = create_knowledge(db, is_published=True)
            second = create_knowledge(db, is_published=True)
            db.add(make_history(knowledge_id=first.id))
            db.add(make_history(knowledge_id=second.id))
            db.commit()
            first_id = first.id

        response = api_client.delete(
            f"{HISTORY}/{first_id}", headers=auth_header(token)
        )

        assert response.status_code == 204
        body = api_client.get(HISTORY, headers=auth_header(token)).json()
        assert body["total"] == 1

    def test_removing_something_never_viewed_is_still_a_204(
        self, api_client: TestClient, token: str
    ):
        """幂等：用户要的是「这条不在我的历史里」，这个状态已经成立了。"""
        response = api_client.delete(f"{HISTORY}/999999", headers=auth_header(token))

        assert response.status_code == 204

    def test_clearing_removes_everything(
        self, api_client: TestClient, session_factory: sessionmaker[Session],
        token: str,
    ):
        with session_factory() as db:
            prepare_categories(db)
            for _ in range(3):
                item = create_knowledge(db, is_published=True)
                db.add(make_history(knowledge_id=item.id))
            db.commit()

        response = api_client.delete(HISTORY, headers=auth_header(token))

        assert response.status_code == 204
        assert (
            api_client.get(HISTORY, headers=auth_header(token)).json()["total"] == 0
        )
        assert history_count(session_factory) == 0

    def test_clearing_when_already_empty_is_still_a_204(
        self, api_client: TestClient, token: str
    ):
        response = api_client.delete(HISTORY, headers=auth_header(token))

        assert response.status_code == 204


class TestIsolationBetweenUsers:
    """历史是私密的：看过什么、什么时候看的，都不该被别人读到。"""

    def test_a_user_cannot_see_another_users_history(
        self, api_client: TestClient, session_factory: sessionmaker[Session],
        published: int,
    ):
        alice = register(api_client, "alice")
        bob = register(api_client, "bob")
        view(api_client, published, alice)

        body = api_client.get(HISTORY, headers=auth_header(bob)).json()

        assert body["total"] == 0
        assert body["items"] == []

    def test_a_user_cannot_delete_another_users_history(
        self, api_client: TestClient, session_factory: sessionmaker[Session],
        published: int,
    ):
        alice = register(api_client, "alice")
        bob = register(api_client, "bob")
        view(api_client, published, alice)

        response = api_client.delete(
            f"{HISTORY}/{published}", headers=auth_header(bob)
        )

        # 返回 204 是因为幂等（Bob 的历史里确实没有这一条），
        # 但**数据必须还在** —— 这一条才是关键
        assert response.status_code == 204
        assert history_count(session_factory) == 1
        assert (
            api_client.get(HISTORY, headers=auth_header(alice)).json()["total"] == 1
        )

    def test_clearing_only_clears_my_own(
        self, api_client: TestClient, session_factory: sessionmaker[Session],
        published: int,
    ):
        """这是本模块破坏性最强的操作：漏掉 user_id 就是清空所有人的历史。"""
        alice = register(api_client, "alice")
        bob = register(api_client, "bob")
        view(api_client, published, alice)
        view(api_client, published, bob)
        assert history_count(session_factory) == 2

        api_client.delete(HISTORY, headers=auth_header(bob))

        assert (
            api_client.get(HISTORY, headers=auth_header(alice)).json()["total"] == 1
        )
        assert history_count(session_factory) == 1

    def test_the_same_knowledge_is_recorded_separately_per_user(
        self, api_client: TestClient, session_factory: sessionmaker[Session],
        published: int,
    ):
        """UNIQUE(user_id, knowledge_id) 是「每人一条」而不是「每篇一条」。"""
        alice = register(api_client, "alice")
        bob = register(api_client, "bob")

        view(api_client, published, alice)
        view(api_client, published, bob)

        assert history_count(session_factory) == 2
        for name in ("alice", "bob"):
            token = api_client.post(
                "/api/auth/login",
                json={"username": name, "password": GOOD_PASSWORD},
            ).json()["access_token"]
            assert (
                api_client.get(HISTORY, headers=auth_header(token)).json()["total"]
                == 1
            )
