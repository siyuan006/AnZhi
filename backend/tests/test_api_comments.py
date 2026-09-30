"""评论接口的测试（docs/API.md 第 7 节，阶段 12b）。

重点在四件事：

 · **读公开、写要登录**：评论列表和帖子一样匿名可读，
   发表必须登录。这条边界反了会很难看 —— 要么社区看不了，
   要么任何人都能顶着别人的名字发言。
 · **评论数是真数字**：`posts.comment_count` 是冗余计数，
   发一条就该涨一条。它错了不会报错，只会让列表上的数字骗人。
 · **空白评论不算评论**：只有空格、换行的内容必须在入口就被拒，
   否则帖子里会出现一串点不动的空白。
 · **隐藏帖子的评论不外泄**：和帖子本身一样按 404 处理。
"""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import func, select
from sqlalchemy.orm import Session, sessionmaker

from app.database.base import utcnow
from app.models.comment import Comment
from app.models.post import Post
from app.services.community.comment_service import MAX_LENGTH
from tests.factories import create_comment, create_post, create_user, prepare_categories

GOOD_PASSWORD = "hunter2hunter2"


def register(client: TestClient, username: str, nickname: str | None = None) -> str:
    payload: dict[str, str] = {"username": username, "password": GOOD_PASSWORD}
    if nickname is not None:
        payload["nickname"] = nickname
    response = client.post("/api/auth/register", json=payload)
    assert response.status_code == 201, response.text
    return response.json()["access_token"]


def register_alice(client: TestClient) -> str:
    """带昵称的账号。

    昵称是特意设的：不设的话署名会退回用户名，「响应里没有 username」
    这条断言就永远是绿的 —— 因为它和该出现的东西长得一模一样。
    """
    return register(client, "alice", nickname="小艾")


def auth_header(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def comments_url(post_id: int) -> str:
    return f"/api/posts/{post_id}/comments"


@pytest.fixture
def token(api_client: TestClient) -> str:
    return register_alice(api_client)


@pytest.fixture
def post(session_factory: sessionmaker[Session]) -> int:
    with session_factory() as db:
        author = create_user(db, username="bob", nickname="小艾")
        return create_post(db, user_id=author.id).id


def comment_count_in_db(session_factory: sessionmaker[Session], post_id: int) -> int:
    with session_factory() as db:
        return db.scalar(
            select(func.count()).select_from(Comment).where(Comment.post_id == post_id)
        ) or 0


def stored_comment_count(
    session_factory: sessionmaker[Session], post_id: int
) -> int:
    with session_factory() as db:
        return db.get(Post, post_id).comment_count


class TestReading:
    def test_anonymous_can_read_comments(self, api_client: TestClient, post: int):
        response = api_client.get(comments_url(post))

        assert response.status_code == 200
        assert response.json()["total"] == 0

    def test_a_post_without_comments_is_an_empty_page(
        self, api_client: TestClient, post: int
    ):
        body = api_client.get(comments_url(post)).json()

        assert body["items"] == []
        assert body["total"] == 0

    def test_comments_come_back_oldest_first(
        self, api_client: TestClient, session_factory: sessionmaker[Session], post: int
    ):
        """评论按时间正序 —— 与帖子列表相反。

        帖子是「最新发生了什么」，评论是「这场对话怎么走到这里的」，
        倒着读接不上。
        """
        base = utcnow()
        with session_factory() as db:
            author = create_user(db, username="carol")
            for index in range(3):
                create_comment(
                    db,
                    post_id=post,
                    user_id=author.id,
                    content=f"第 {index} 条",
                    created_at=base.replace(microsecond=index * 1000),
                )

        contents = [item["content"] for item in api_client.get(comments_url(post)).json()["items"]]

        assert contents == ["第 0 条", "第 1 条", "第 2 条"]

    def test_username_is_not_exposed(self, api_client: TestClient, post: int, token: str):
        api_client.post(
            comments_url(post),
            json={"content": "说说我的看法"},
            headers=auth_header(token),
        )

        response = api_client.get(comments_url(post))

        assert response.json()["items"][0]["author"]["name"] == "小艾"
        assert "alice" not in response.text

    def test_missing_post_is_404(self, api_client: TestClient):
        response = api_client.get(comments_url(999999))

        assert response.status_code == 404
        assert response.json()["detail"] == "帖子不存在或已删除"

    def test_hidden_post_comments_are_404_too(
        self, api_client: TestClient, session_factory: sessionmaker[Session]
    ):
        with session_factory() as db:
            author = create_user(db, username="dave")
            hidden = create_post(db, user_id=author.id, is_published=False)
            create_comment(db, post_id=hidden.id, user_id=author.id)

        response = api_client.get(comments_url(hidden.id))

        assert response.status_code == 404

    def test_paging_reports_the_full_total(
        self, api_client: TestClient, session_factory: sessionmaker[Session], post: int
    ):
        with session_factory() as db:
            author = create_user(db, username="erin")
            for index in range(5):
                create_comment(db, post_id=post, user_id=author.id, content=f"c{index}")

        body = api_client.get(comments_url(post), params={"page": 2, "page_size": 2}).json()

        assert body["total"] == 5
        assert len(body["items"]) == 2


class TestWriting:
    def test_anonymous_cannot_post_a_comment(self, api_client: TestClient, post: int):
        response = api_client.post(comments_url(post), json={"content": "路过"})

        assert response.status_code == 401
        assert response.json()["detail"] == "请先登录"

    def test_posting_returns_the_comment_with_its_author(
        self, api_client: TestClient, post: int, token: str
    ):
        response = api_client.post(
            comments_url(post),
            json={"content": "补一句：拔掉充电器再出门"},
            headers=auth_header(token),
        )

        assert response.status_code == 201
        body = response.json()
        assert body["content"] == "补一句：拔掉充电器再出门"
        assert body["author"]["name"] == "小艾"
        assert body["created_at"]

    def test_the_comment_shows_up_in_the_list(
        self, api_client: TestClient, post: int, token: str
    ):
        api_client.post(
            comments_url(post), json={"content": "已阅"}, headers=auth_header(token)
        )

        body = api_client.get(comments_url(post)).json()

        assert body["total"] == 1
        assert body["items"][0]["content"] == "已阅"

    def test_comment_count_on_the_post_goes_up(
        self, api_client: TestClient, session_factory: sessionmaker[Session], post: int, token: str
    ):
        assert stored_comment_count(session_factory, post) == 0

        api_client.post(
            comments_url(post), json={"content": "第一条"}, headers=auth_header(token)
        )
        assert stored_comment_count(session_factory, post) == 1

        api_client.post(
            comments_url(post), json={"content": "第二条"}, headers=auth_header(token)
        )
        assert stored_comment_count(session_factory, post) == 2

    def test_the_counter_matches_the_rows_not_just_the_increment(
        self, api_client: TestClient, session_factory: sessionmaker[Session], post: int, token: str
    ):
        """计数是照着真实行数写的，不是在旧值上盲目加一。

        直接造两条评论（绕过 service，计数不会跟着动），再发一条 ——
        对完之后计数必须等于真实行数，而不是「0 + 1」。
        """
        with session_factory() as db:
            author = create_user(db, username="frank")
            for index in range(2):
                create_comment(db, post_id=post, user_id=author.id, content=f"旧的 {index}")

        api_client.post(
            comments_url(post), json={"content": "新的一条"}, headers=auth_header(token)
        )

        assert stored_comment_count(session_factory, post) == comment_count_in_db(
            session_factory, post
        )
        assert stored_comment_count(session_factory, post) == 3

    def test_surrounding_whitespace_is_trimmed(
        self, api_client: TestClient, post: int, token: str
    ):
        response = api_client.post(
            comments_url(post),
            json={"content": "  前后都有空格  \n"},
            headers=auth_header(token),
        )

        assert response.json()["content"] == "前后都有空格"

    @pytest.mark.parametrize("blank", ["", "   ", "\n\n", "\t "])
    def test_blank_comments_are_rejected(
        self, api_client: TestClient, post: int, token: str, blank: str
    ):
        response = api_client.post(
            comments_url(post), json={"content": blank}, headers=auth_header(token)
        )

        assert response.status_code == 422

    def test_whitespace_only_never_reaches_the_database(
        self, api_client: TestClient, session_factory: sessionmaker[Session], post: int, token: str
    ):
        api_client.post(
            comments_url(post), json={"content": "   "}, headers=auth_header(token)
        )

        assert comment_count_in_db(session_factory, post) == 0
        assert stored_comment_count(session_factory, post) == 0

    def test_overlong_comments_are_rejected(
        self, api_client: TestClient, post: int, token: str
    ):
        response = api_client.post(
            comments_url(post),
            json={"content": "字" * (MAX_LENGTH + 1)},
            headers=auth_header(token),
        )

        assert response.status_code == 422

    def test_the_length_limit_counts_the_trimmed_text(
        self, api_client: TestClient, post: int, token: str
    ):
        response = api_client.post(
            comments_url(post),
            json={"content": "  " + "字" * MAX_LENGTH + "  "},
            headers=auth_header(token),
        )

        assert response.status_code == 201
        assert len(response.json()["content"]) == MAX_LENGTH

    def test_posting_to_a_missing_post_is_404(
        self, api_client: TestClient, token: str
    ):
        response = api_client.post(
            comments_url(999999), json={"content": "你好"}, headers=auth_header(token)
        )

        assert response.status_code == 404
        assert response.json()["detail"] == "帖子不存在或已删除"

    def test_a_rejected_comment_leaves_nothing_behind(
        self, api_client: TestClient, session_factory: sessionmaker[Session], token: str
    ):
        api_client.post(
            comments_url(999999), json={"content": "你好"}, headers=auth_header(token)
        )

        with session_factory() as db:
            assert db.scalar(select(func.count()).select_from(Comment)) == 0

    def test_two_users_get_their_own_names(
        self, api_client: TestClient, post: int, token: str
    ):
        """评论的作者是**登录的那个人**，不是请求里说了算的。"""
        other = register(api_client, "mallory", nickname="陌生人")
        api_client.post(
            comments_url(post),
            json={"content": "我是小艾", "author": {"id": 1, "name": "小艾"}},
            headers=auth_header(other),
        )

        body = api_client.get(comments_url(post)).json()

        assert body["items"][0]["author"]["name"] == "陌生人"
