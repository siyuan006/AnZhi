"""发帖 / 我的帖子 / 删帖的接口测试（docs/API.md 第 7 节，阶段 12d）。

重点：

 · **写必须登录**，读不用 —— 与社区其他接口一致。
 · **校验的是规范化之后的文本。** 标题压成单行、正文保留分段；
   长度按处理后的值算，否则「前后多打了空格」会被判超长
   （阶段 12b 的评论区踩过这个坑）。
 · **删帖是软删除。** 行留在库里，点赞与评论不会变成指向空气的外键。
 · **删别人的帖子是 403 而不是 404**：已发布的帖子人人看得见，
   假装它不存在只会让作者困惑。
 · **`/api/posts/mine` 不能被 `/{post_id}` 吃掉。**
"""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import func, select
from sqlalchemy.orm import Session, sessionmaker

from app.models.comment import Comment
from app.models.like import Like
from app.models.post import Post
from app.services.community import post_service
from tests.factories import create_post, create_user, prepare_categories

GOOD_PASSWORD = "hunter2hunter2"


def register(client: TestClient, username: str, nickname: str | None = None) -> str:
    body: dict[str, object] = {"username": username, "password": GOOD_PASSWORD}
    if nickname is not None:
        body["nickname"] = nickname
    response = client.post("/api/auth/register", json=body)
    assert response.status_code == 201, response.text
    return response.json()["access_token"]


def auth_header(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture
def token(api_client: TestClient) -> str:
    """带昵称注册。

    不设昵称的话署名会**等于用户名**，「响应里没有泄露登录名」
    这条断言就永远成立，测不出任何东西 —— 阶段 12b 踩过这个坑。
    """
    return register(api_client, "alice", nickname="小艾")


@pytest.fixture
def other_token(api_client: TestClient) -> str:
    return register(api_client, "bob")


@pytest.fixture
def categories(session_factory: sessionmaker[Session]) -> None:
    with session_factory() as db:
        prepare_categories(db)


def publish(
    client: TestClient,
    token: str,
    *,
    title: str = "宿舍用电的几点提醒",
    content: str = "不要在一个插排上同时接大功率电器。",
    category_id: int | None = None,
):
    body: dict[str, object] = {"title": title, "content": content}
    if category_id is not None:
        body["category_id"] = category_id
    return client.post("/api/posts", json=body, headers=auth_header(token))


class TestPublishing:
    def test_publishing_returns_the_full_post(self, api_client: TestClient, token: str):
        response = publish(api_client, token)

        assert response.status_code == 201, response.text
        body = response.json()
        assert body["title"] == "宿舍用电的几点提醒"
        assert body["content"] == "不要在一个插排上同时接大功率电器。"
        assert body["like_count"] == 0
        assert body["comment_count"] == 0
        assert body["is_liked"] is False, "刚发出来的帖子自己当然没点过赞"

    def test_the_new_post_shows_up_at_the_top_of_the_list(
        self, api_client: TestClient, session_factory: sessionmaker[Session], token: str
    ):
        with session_factory() as db:
            author = create_user(db, username="carol")
            create_post(db, user_id=author.id, title="更早的一条")

        publish(api_client, token, title="刚发的这一条")

        listed = api_client.get("/api/posts").json()["items"]

        assert listed[0]["title"] == "刚发的这一条"

    def test_the_list_row_has_no_content_but_the_detail_does(
        self, api_client: TestClient, token: str
    ):
        created = publish(api_client, token, content="正文只在详情里出现").json()

        listed = api_client.get("/api/posts").json()["items"][0]
        assert "content" not in listed, "列表项不该带正文"

        detail = api_client.get(f"/api/posts/{created['id']}").json()
        assert detail["content"] == "正文只在详情里出现"

    def test_publishing_needs_a_login(self, api_client: TestClient):
        response = api_client.post(
            "/api/posts", json={"title": "标题", "content": "正文"}
        )

        assert response.status_code == 401
        assert response.json()["detail"] == "请先登录"

    def test_the_response_never_leaks_the_username(
        self, api_client: TestClient, token: str
    ):
        response = publish(api_client, token)

        assert response.json()["author"]["name"] == "小艾", "署名应该是昵称"
        assert "alice" not in response.text, "作者署名不该是登录名"


class TestTitleValidation:
    def test_an_empty_title_is_rejected(self, api_client: TestClient, token: str):
        response = publish(api_client, token, title="")

        assert response.status_code == 422

    def test_a_whitespace_only_title_is_rejected(
        self, api_client: TestClient, token: str
    ):
        response = publish(api_client, token, title="   \n  ")

        assert response.status_code == 422

    def test_a_title_of_exactly_the_limit_is_accepted(
        self, api_client: TestClient, token: str
    ):
        title = "标" * post_service.TITLE_MAX_LENGTH

        response = publish(api_client, token, title=title)

        assert response.status_code == 201, response.text

    def test_a_title_one_over_the_limit_is_rejected(
        self, api_client: TestClient, token: str
    ):
        title = "标" * (post_service.TITLE_MAX_LENGTH + 1)

        response = publish(api_client, token, title=title)

        assert response.status_code == 422

    def test_the_length_limit_counts_the_trimmed_title(
        self, api_client: TestClient, token: str
    ):
        """前后多打的空格不该把标题顶超长。

        校验若写在 `Field(max_length=…)` 上，它作用在**原始值**上，
        而且早于 validator —— 这条就会挂。
        """
        title = "  " + "标" * post_service.TITLE_MAX_LENGTH + "  "

        response = publish(api_client, token, title=title)

        assert response.status_code == 201, response.text

    def test_a_multiline_title_is_collapsed_to_one_line(
        self, api_client: TestClient, token: str
    ):
        """标题必须是单行 —— 带换行会把卡片布局撑破。"""
        body = publish(api_client, token, title="第一行\n\n第二行").json()

        assert body["title"] == "第一行 第二行"


class TestContentValidation:
    def test_an_empty_content_is_rejected(self, api_client: TestClient, token: str):
        response = publish(api_client, token, content="")

        assert response.status_code == 422

    def test_a_whitespace_only_content_is_rejected(
        self, api_client: TestClient, token: str
    ):
        response = publish(api_client, token, content=" \n ")

        assert response.status_code == 422

    def test_a_content_of_exactly_the_limit_is_accepted(
        self, api_client: TestClient, token: str
    ):
        content = "文" * post_service.CONTENT_MAX_LENGTH

        response = publish(api_client, token, content=content)

        assert response.status_code == 201, response.text

    def test_a_content_one_over_the_limit_is_rejected(
        self, api_client: TestClient, token: str
    ):
        content = "文" * (post_service.CONTENT_MAX_LENGTH + 1)

        response = publish(api_client, token, content=content)

        assert response.status_code == 422

    def test_the_length_limit_counts_the_trimmed_content(
        self, api_client: TestClient, token: str
    ):
        content = "\n\n" + "文" * post_service.CONTENT_MAX_LENGTH + "\n\n"

        response = publish(api_client, token, content=content)

        assert response.status_code == 201, response.text

    def test_paragraph_breaks_survive(self, api_client: TestClient, token: str):
        """正文分段是用户有意写的，不能像标题那样被折叠掉。"""
        body = publish(
            api_client, token, content="第一段。\n\n第二段。\n第三行。"
        ).json()

        assert body["content"] == "第一段。\n\n第二段。\n第三行。"

    def test_windows_line_endings_are_normalised(
        self, api_client: TestClient, token: str
    ):
        body = publish(api_client, token, content="第一段。\r\n第二段。").json()

        assert "\r" not in body["content"]
        assert body["content"] == "第一段。\n第二段。"

    def test_surrounding_whitespace_is_stripped(
        self, api_client: TestClient, token: str
    ):
        body = publish(api_client, token, content="\n  正文  \n").json()

        assert body["content"] == "正文"


class TestCategory:
    def test_a_post_can_have_no_category(
        self, api_client: TestClient, categories: None, token: str
    ):
        body = publish(api_client, token).json()

        assert body["category_id"] is None
        assert body["category_name"] is None

    def test_a_valid_category_comes_back_with_its_name(
        self, api_client: TestClient, categories: None, token: str
    ):
        body = publish(api_client, token, category_id=1).json()

        assert body["category_id"] == 1
        assert body["category_name"], "分类名要带回来，列表页靠它画标签"

    def test_an_unknown_category_is_404_not_500(
        self, api_client: TestClient, categories: None, token: str
    ):
        """不校验的话外键约束会在 commit 时抛 IntegrityError，用户看到 500。"""
        response = publish(api_client, token, category_id=999999)

        assert response.status_code == 404
        assert response.json()["detail"] == "分类不存在"

    def test_a_rejected_category_leaves_no_post(
        self, api_client: TestClient, session_factory: sessionmaker[Session], token: str
    ):
        publish(api_client, token, category_id=999999)

        with session_factory() as db:
            assert db.scalar(select(func.count()).select_from(Post)) == 0


class TestMyPosts:
    def test_the_mine_route_is_not_swallowed_by_the_id_route(
        self, api_client: TestClient
    ):
        """`/mine` 必须声明在 `/{post_id}` 之前。

        FastAPI 按注册顺序匹配，顺序反了的话 `/mine` 会被当成
        `post_id` 去解析 int，返回 422 而不是「请先登录」。
        """
        response = api_client.get("/api/posts/mine")

        assert response.status_code == 401, (
            f"拿到 {response.status_code} —— routing 顺序可能反了，"
            "/mine 被 /{post_id} 吃掉了"
        )

    def test_mine_needs_a_login(self, api_client: TestClient):
        response = api_client.get("/api/posts/mine")

        assert response.json()["detail"] == "请先登录"

    def test_mine_returns_only_my_own_posts(
        self,
        api_client: TestClient,
        session_factory: sessionmaker[Session],
        token: str,
        other_token: str,
    ):
        publish(api_client, token, title="我发的")
        publish(api_client, other_token, title="别人发的")

        items = api_client.get(
            "/api/posts/mine", headers=auth_header(token)
        ).json()["items"]

        assert [item["title"] for item in items] == ["我发的"]

    def test_mine_is_newest_first(
        self, api_client: TestClient, token: str
    ):
        publish(api_client, token, title="先发的")
        publish(api_client, token, title="后发的")

        items = api_client.get(
            "/api/posts/mine", headers=auth_header(token)
        ).json()["items"]

        assert [item["title"] for item in items] == ["后发的", "先发的"]

    def test_the_total_counts_only_my_posts(
        self,
        api_client: TestClient,
        session_factory: sessionmaker[Session],
        token: str,
        other_token: str,
    ):
        publish(api_client, token, title="我发的")
        publish(api_client, other_token, title="别人发的")

        body = api_client.get("/api/posts/mine", headers=auth_header(token)).json()

        assert body["total"] == 1

    def test_the_row_has_no_content(self, api_client: TestClient, token: str):
        publish(api_client, token)

        item = api_client.get(
            "/api/posts/mine", headers=auth_header(token)
        ).json()["items"][0]

        assert "content" not in item

    def test_a_deleted_post_is_gone_from_mine_too(
        self, api_client: TestClient, token: str
    ):
        created = publish(api_client, token).json()
        api_client.delete(f"/api/posts/{created['id']}", headers=auth_header(token))

        body = api_client.get("/api/posts/mine", headers=auth_header(token)).json()

        assert body["total"] == 0, "删掉了就该看不见，对自己也一样"


class TestDeleting:
    def test_the_author_can_delete_and_gets_204(
        self, api_client: TestClient, token: str
    ):
        created = publish(api_client, token).json()

        response = api_client.delete(
            f"/api/posts/{created['id']}", headers=auth_header(token)
        )

        assert response.status_code == 204

    def test_the_post_disappears_from_every_entry_point(
        self, api_client: TestClient, token: str
    ):
        """列表、详情、评论、点赞四个入口都经过同一个过滤条件。

        少一个的话，删掉的帖子会从某个角落里冒出来。
        """
        created = publish(api_client, token).json()
        post_id = created["id"]
        api_client.delete(f"/api/posts/{post_id}", headers=auth_header(token))

        assert api_client.get("/api/posts").json()["total"] == 0
        assert api_client.get(f"/api/posts/{post_id}").status_code == 404
        assert api_client.get(f"/api/posts/{post_id}/comments").status_code == 404
        assert (
            api_client.post(
                f"/api/posts/{post_id}/like", headers=auth_header(token)
            ).status_code
            == 404
        )

    def test_deleting_twice_is_404_the_second_time(
        self, api_client: TestClient, token: str
    ):
        created = publish(api_client, token).json()
        url = f"/api/posts/{created['id']}"

        api_client.delete(url, headers=auth_header(token))
        again = api_client.delete(url, headers=auth_header(token))

        assert again.status_code == 404

    def test_deleting_someone_elses_post_is_403(
        self, api_client: TestClient, token: str, other_token: str
    ):
        created = publish(api_client, token).json()

        response = api_client.delete(
            f"/api/posts/{created['id']}", headers=auth_header(other_token)
        )

        assert response.status_code == 403
        assert response.json()["detail"] == "只能删除自己的帖子"

    def test_a_rejected_delete_does_not_remove_anything(
        self, api_client: TestClient, token: str, other_token: str
    ):
        created = publish(api_client, token).json()

        api_client.delete(
            f"/api/posts/{created['id']}", headers=auth_header(other_token)
        )

        assert api_client.get(f"/api/posts/{created['id']}").status_code == 200

    def test_deleting_a_missing_post_is_404(self, api_client: TestClient, token: str):
        response = api_client.delete("/api/posts/999999", headers=auth_header(token))

        assert response.status_code == 404

    def test_deleting_needs_a_login(self, api_client: TestClient, token: str):
        created = publish(api_client, token).json()

        response = api_client.delete(f"/api/posts/{created['id']}")

        assert response.status_code == 401

    def test_deleting_is_a_soft_delete(
        self,
        api_client: TestClient,
        session_factory: sessionmaker[Session],
        token: str,
    ):
        """行还在库里，只是 is_published 变成 False。"""
        created = publish(api_client, token).json()
        api_client.delete(f"/api/posts/{created['id']}", headers=auth_header(token))

        with session_factory() as db:
            row = db.get(Post, created["id"])
            assert row is not None, "硬删的话点赞和评论会变成指向空气的外键"
            assert row.is_published is False

    def test_likes_and_comments_survive_the_delete(
        self,
        api_client: TestClient,
        session_factory: sessionmaker[Session],
        token: str,
        other_token: str,
    ):
        created = publish(api_client, token).json()
        post_id = created["id"]
        api_client.post(
            f"/api/posts/{post_id}/comments",
            json={"content": "补充一点。"},
            headers=auth_header(other_token),
        )
        api_client.post(f"/api/posts/{post_id}/like", headers=auth_header(other_token))

        api_client.delete(f"/api/posts/{post_id}", headers=auth_header(token))

        with session_factory() as db:
            comments = db.scalar(select(func.count()).select_from(Comment))
            likes = db.scalar(select(func.count()).select_from(Like))
            assert comments == 1
            assert likes == 1
