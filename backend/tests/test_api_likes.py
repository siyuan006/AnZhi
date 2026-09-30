"""点赞接口的测试（docs/API.md 第 7 节，阶段 12c）。

重点：

 · **幂等**：重复点赞不会多出第二个赞，重复取消也不报错。
   数据库上的 `UNIQUE(post_id, user_id)` 是最后一道防线，
   但接口不能把约束冲突原样漏成 500。
 · **数字要对得上**：`like_count` 是列表上显示给用户的数字，
   而且它和 `likes` 表里的行数必须一致。
 · **按人算**：`is_liked` 是「我点没点过」，不是「有没有人点过」。
   前者写错的话，所有人都看到自己的爱心是亮的。
 · **列表与详情口径一致**：两处都返回 `is_liked`，
   否则同一篇帖子在详情页是实心、回到列表变成空心。
 · **未登录不能点**，但**能看**。
"""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import func, select
from sqlalchemy.orm import Session, sessionmaker

from app.models.like import Like
from app.models.post import Post
from tests.factories import create_post, create_user

GOOD_PASSWORD = "hunter2hunter2"


def register(client: TestClient, username: str) -> str:
    response = client.post(
        "/api/auth/register",
        json={"username": username, "password": GOOD_PASSWORD},
    )
    assert response.status_code == 201, response.text
    return response.json()["access_token"]


def auth_header(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def like_url(post_id: int) -> str:
    return f"/api/posts/{post_id}/like"


@pytest.fixture
def token(api_client: TestClient) -> str:
    return register(api_client, "alice")


@pytest.fixture
def post(session_factory: sessionmaker[Session]) -> int:
    with session_factory() as db:
        author = create_user(db, username="bob", nickname="小艾")
        return create_post(db, user_id=author.id).id


def like_rows(session_factory: sessionmaker[Session], post_id: int) -> int:
    with session_factory() as db:
        return db.scalar(
            select(func.count()).select_from(Like).where(Like.post_id == post_id)
        ) or 0


def stored_count(session_factory: sessionmaker[Session], post_id: int) -> int:
    with session_factory() as db:
        return db.get(Post, post_id).like_count


class TestLiking:
    def test_liking_returns_the_new_count(
        self, api_client: TestClient, post: int, token: str
    ):
        response = api_client.post(like_url(post), headers=auth_header(token))

        assert response.status_code == 201
        assert response.json() == {"like_count": 1, "is_liked": True}

    def test_liking_twice_does_not_add_a_second_like(
        self, api_client: TestClient, session_factory: sessionmaker[Session], post: int, token: str
    ):
        api_client.post(like_url(post), headers=auth_header(token))
        again = api_client.post(like_url(post), headers=auth_header(token))

        assert again.status_code == 200, "重复点赞应当是 200，不是又建了一个"
        assert again.json()["like_count"] == 1
        assert like_rows(session_factory, post) == 1

    def test_two_users_each_add_one(
        self, api_client: TestClient, session_factory: sessionmaker[Session], post: int, token: str
    ):
        other = register(api_client, "carol")

        api_client.post(like_url(post), headers=auth_header(token))
        second = api_client.post(like_url(post), headers=auth_header(other))

        assert second.json()["like_count"] == 2
        assert like_rows(session_factory, post) == 2

    def test_the_counter_matches_the_rows(
        self, api_client: TestClient, session_factory: sessionmaker[Session], post: int, token: str
    ):
        """计数不是「旧值 +1」，是按真实行数写的。

        先直接造两个赞（绕过 service，计数不会跟着动），再点一次 ——
        对完之后计数必须等于真实行数，而不是「0 + 1」。
        """
        with session_factory() as db:
            for name in ("dave", "erin"):
                user = create_user(db, username=name)
                db.add(Like(post_id=post, user_id=user.id))
            db.commit()

        response = api_client.post(like_url(post), headers=auth_header(token))

        assert response.json()["like_count"] == 3
        assert stored_count(session_factory, post) == 3

    def test_anonymous_cannot_like(self, api_client: TestClient, post: int):
        response = api_client.post(like_url(post))

        assert response.status_code == 401
        assert response.json()["detail"] == "请先登录"

    def test_anonymous_cannot_unlike(self, api_client: TestClient, post: int):
        response = api_client.delete(like_url(post))

        assert response.status_code == 401

    def test_liking_a_missing_post_is_404(self, api_client: TestClient, token: str):
        response = api_client.post(like_url(999999), headers=auth_header(token))

        assert response.status_code == 404

    def test_liking_a_hidden_post_is_404_too(
        self, api_client: TestClient, session_factory: sessionmaker[Session], token: str
    ):
        with session_factory() as db:
            author = create_user(db, username="frank")
            hidden = create_post(db, user_id=author.id, is_published=False)

        response = api_client.post(like_url(hidden.id), headers=auth_header(token))

        assert response.status_code == 404

    def test_a_rejected_like_leaves_no_row(
        self, api_client: TestClient, session_factory: sessionmaker[Session], token: str
    ):
        api_client.post(like_url(999999), headers=auth_header(token))

        with session_factory() as db:
            assert db.scalar(select(func.count()).select_from(Like)) == 0


class TestUnliking:
    def test_unliking_removes_it_and_returns_the_new_count(
        self, api_client: TestClient, session_factory: sessionmaker[Session], post: int, token: str
    ):
        api_client.post(like_url(post), headers=auth_header(token))

        response = api_client.delete(like_url(post), headers=auth_header(token))

        assert response.status_code == 200
        assert response.json() == {"like_count": 0, "is_liked": False}
        assert like_rows(session_factory, post) == 0

    def test_unliking_without_having_liked_is_not_an_error(
        self, api_client: TestClient, post: int, token: str
    ):
        response = api_client.delete(like_url(post), headers=auth_header(token))

        assert response.status_code == 200
        assert response.json() == {"like_count": 0, "is_liked": False}

    def test_unliking_twice_is_fine(
        self, api_client: TestClient, post: int, token: str
    ):
        api_client.post(like_url(post), headers=auth_header(token))
        api_client.delete(like_url(post), headers=auth_header(token))

        response = api_client.delete(like_url(post), headers=auth_header(token))

        assert response.status_code == 200

    def test_one_user_unliking_leaves_the_others(
        self, api_client: TestClient, post: int, token: str
    ):
        other = register(api_client, "carol")
        api_client.post(like_url(post), headers=auth_header(token))
        api_client.post(like_url(post), headers=auth_header(other))

        response = api_client.delete(like_url(post), headers=auth_header(token))

        assert response.json()["like_count"] == 1

    def test_unliking_a_missing_post_is_404(self, api_client: TestClient, token: str):
        response = api_client.delete(like_url(999999), headers=auth_header(token))

        assert response.status_code == 404


class TestIsLiked:
    def test_anonymous_detail_says_not_liked(
        self, api_client: TestClient, post: int, token: str
    ):
        api_client.post(like_url(post), headers=auth_header(token))

        body = api_client.get(f"/api/posts/{post}").json()

        assert body["is_liked"] is False, "没有身份就谈不上「我点过」"
        assert body["like_count"] == 1, "但赞数照常要显示"

    def test_detail_says_liked_for_the_person_who_liked(
        self, api_client: TestClient, post: int, token: str
    ):
        api_client.post(like_url(post), headers=auth_header(token))

        body = api_client.get(
            f"/api/posts/{post}", headers=auth_header(token)
        ).json()

        assert body["is_liked"] is True

    def test_is_liked_is_per_person_not_per_post(
        self, api_client: TestClient, post: int, token: str
    ):
        """别人点过，我这边依然是没点过。

        写成「有没有人点过」的话，所有人都会看到自己的爱心是亮的，
        再点一下反而变成取消别人的赞。
        """
        other = register(api_client, "carol")
        api_client.post(like_url(post), headers=auth_header(other))

        body = api_client.get(
            f"/api/posts/{post}", headers=auth_header(token)
        ).json()

        assert body["like_count"] == 1
        assert body["is_liked"] is False

    def test_unliking_turns_it_back_off(
        self, api_client: TestClient, post: int, token: str
    ):
        api_client.post(like_url(post), headers=auth_header(token))
        api_client.delete(like_url(post), headers=auth_header(token))

        body = api_client.get(
            f"/api/posts/{post}", headers=auth_header(token)
        ).json()

        assert body["is_liked"] is False


class TestIsLikedInTheList:
    """列表页上就有点赞按钮，因此列表也必须带 `is_liked`。

    只让详情页带的话，同一篇帖子在详情页是实心、回到列表变成空心，
    用户会以为点赞没生效。
    """

    def _items(
        self, api_client: TestClient, headers: dict[str, str] | None = None
    ) -> dict[int, dict]:
        response = api_client.get("/api/posts", headers=headers)
        assert response.status_code == 200, response.text
        return {row["id"]: row for row in response.json()["items"]}

    def test_anonymous_list_says_not_liked_but_still_counts(
        self, api_client: TestClient, post: int, token: str
    ):
        api_client.post(like_url(post), headers=auth_header(token))

        row = self._items(api_client)[post]

        assert row["like_count"] == 1, "赞数照常要显示"
        assert row["is_liked"] is False, "没有身份就谈不上「我点过」"

    def test_only_the_post_i_liked_is_marked(
        self, api_client: TestClient, session_factory: sessionmaker[Session], post: int, token: str
    ):
        """一篇点过、一篇没点过，只有前者是亮的。

        整页统一给 true（或统一给 false）都会让这条挂掉。
        """
        with session_factory() as db:
            author = create_user(db, username="grace", nickname="小周")
            untouched = create_post(db, user_id=author.id).id

        api_client.post(like_url(post), headers=auth_header(token))

        items = self._items(api_client, auth_header(token))

        assert items[post]["is_liked"] is True
        assert items[untouched]["is_liked"] is False
        assert items[untouched]["like_count"] == 0

    def test_another_user_does_not_see_my_like(
        self, api_client: TestClient, post: int, token: str
    ):
        other = register(api_client, "carol")
        api_client.post(like_url(post), headers=auth_header(token))

        row = self._items(api_client, auth_header(other))[post]

        assert row["like_count"] == 1
        assert row["is_liked"] is False

    def test_unliking_clears_it_in_the_list_too(
        self, api_client: TestClient, post: int, token: str
    ):
        api_client.post(like_url(post), headers=auth_header(token))
        api_client.delete(like_url(post), headers=auth_header(token))

        row = self._items(api_client, auth_header(token))[post]

        assert row["is_liked"] is False
        assert row["like_count"] == 0

    def test_a_bad_token_does_not_break_the_list(
        self, api_client: TestClient, post: int
    ):
        """token 无效只是「不知道你是谁」，不该让公开列表整页失败。"""
        row = self._items(api_client, auth_header("not-a-real-token"))[post]

        assert row["is_liked"] is False
