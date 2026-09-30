"""社区帖子接口的测试（docs/API.md 第 7 节，阶段 12a）。

12a 只有两个**读**接口，因此测试重点不在权限，而在几件容易做错的事：

 · **不需要登录**：社区是公开内容。这里要明确断言匿名拿到 200，
   而不是「反正没写鉴权所以碰巧能过」—— 将来有人顺手加上
   `Depends(get_current_user)` 时，这条会立刻红。
 · **隐藏的帖子不外泄**：`is_published=False` 的帖子在列表和详情里
   都必须和不存在一样（404），否则等于提供了探测隐藏内容的入口。
 · **不返回正文全文的列表**：列表项只有摘要。这不是省流量的小聪明，
   而是「列表」与「详情」两个接口的职责边界。
 · **摘要与正文一致**：摘要由 content 截断而来，不是独立字段，
   因此不可能出现「摘要说的和正文不一样」。
 · **作者只暴露署名**：响应里不能出现 `username`，
   用户名是登录凭据的一半，不该随帖子公开。
"""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import select
from sqlalchemy.orm import Session, sessionmaker

from app.database.base import utcnow
from app.models import Category
from app.services.community.post_service import SUMMARY_LENGTH
from tests.factories import create_post, create_user, prepare_categories

POSTS = "/api/posts"


@pytest.fixture
def author(session_factory: sessionmaker[Session]) -> int:
    """一个作者，返回它的 id。"""
    with session_factory() as db:
        return create_user(db, username="alice", nickname="小艾").id


def category_ids(db: Session) -> list[int]:
    """六大分类的 id，按顺序。需要合法 category_id 的用例先调它。"""
    prepare_categories(db)
    return list(db.scalars(select(Category.id).order_by(Category.id)))


class TestListing:
    def test_anonymous_can_read_the_list(self, api_client: TestClient):
        """社区不需要登录 —— 这是刻意的，不是漏写鉴权。"""
        response = api_client.get(POSTS)

        assert response.status_code == 200
        assert response.json()["total"] == 0

    def test_empty_community_is_an_empty_page_not_an_error(
        self, api_client: TestClient
    ):
        body = api_client.get(POSTS).json()

        assert body["total"] == 0
        assert body["items"] == []
        assert body["page"] == 1

    def test_newest_first(
        self, api_client: TestClient, session_factory: sessionmaker[Session], author: int
    ):
        with session_factory() as db:
            create_post(db, user_id=author, title="先发的")
            create_post(db, user_id=author, title="后发的")

        titles = [item["title"] for item in api_client.get(POSTS).json()["items"]]

        assert titles == ["后发的", "先发的"]

    def test_hidden_posts_do_not_appear(
        self, api_client: TestClient, session_factory: sessionmaker[Session], author: int
    ):
        with session_factory() as db:
            create_post(db, user_id=author, title="正常帖子")
            create_post(db, user_id=author, title="被隐藏的", is_published=False)

        body = api_client.get(POSTS).json()

        assert body["total"] == 1
        assert [i["title"] for i in body["items"]] == ["正常帖子"]

    def test_list_items_carry_a_summary_not_the_full_content(
        self, api_client: TestClient, session_factory: sessionmaker[Session], author: int
    ):
        """列表只给摘要 —— 「列表」与「详情」的职责边界。"""
        long_content = "安全提示。" * 100
        with session_factory() as db:
            create_post(db, user_id=author, content=long_content)

        item = api_client.get(POSTS).json()["items"][0]

        assert "content" not in item, "列表项不该带正文全文"
        assert item["summary"].endswith("…")
        assert len(item["summary"]) == SUMMARY_LENGTH + 1

    def test_short_content_is_summarised_without_an_ellipsis(
        self, api_client: TestClient, session_factory: sessionmaker[Session], author: int
    ):
        with session_factory() as db:
            create_post(db, user_id=author, content="短短一句话。")

        assert api_client.get(POSTS).json()["items"][0]["summary"] == "短短一句话。"

    def test_summary_collapses_newlines(
        self, api_client: TestClient, session_factory: sessionmaker[Session], author: int
    ):
        """正文里的换行不折叠，摘要首行之后的内容在卡片上会看不见。"""
        with session_factory() as db:
            create_post(db, user_id=author, content="第一行\n\n第二行   第三行")

        assert api_client.get(POSTS).json()["items"][0]["summary"] == "第一行 第二行 第三行"

    def test_items_carry_the_author_display_name(
        self, api_client: TestClient, session_factory: sessionmaker[Session], author: int
    ):
        with session_factory() as db:
            create_post(db, user_id=author)

        item = api_client.get(POSTS).json()["items"][0]

        assert item["author"]["id"] == author
        assert item["author"]["name"] == "小艾", "有昵称时用昵称"

    def test_username_is_not_exposed(
        self, api_client: TestClient, session_factory: sessionmaker[Session], author: int
    ):
        """用户名是登录凭据的一半，不该随帖子公开。"""
        with session_factory() as db:
            create_post(db, user_id=author)

        raw = api_client.get(POSTS).text

        assert "alice" not in raw, "响应里不该出现 username"

    def test_falls_back_to_username_when_no_nickname(
        self, api_client: TestClient, session_factory: sessionmaker[Session]
    ):
        with session_factory() as db:
            uid = create_user(db, username="plainuser", nickname=None).id
            create_post(db, user_id=uid)

        assert api_client.get(POSTS).json()["items"][0]["author"]["name"] == "plainuser"

    def test_filter_by_category(
        self, api_client: TestClient, session_factory: sessionmaker[Session], author: int
    ):
        with session_factory() as db:
            ids = category_ids(db)
            create_post(db, user_id=author, title="消防的", category_id=ids[0])
            create_post(db, user_id=author, title="用电的", category_id=ids[1])

        body = api_client.get(POSTS, params={"category_id": ids[0]}).json()

        assert body["total"] == 1
        assert body["items"][0]["title"] == "消防的"

    def test_filter_by_category_keeps_total_consistent(
        self, api_client: TestClient, session_factory: sessionmaker[Session], author: int
    ):
        """total 与列表必须来自同一组条件，否则会出现「说有 5 条只给 1 条」。"""
        with session_factory() as db:
            ids = category_ids(db)
            for _ in range(3):
                create_post(db, user_id=author, category_id=ids[0])
            create_post(db, user_id=author, category_id=ids[1])

        body = api_client.get(
            POSTS, params={"category_id": ids[0], "page_size": 1}
        ).json()

        assert body["total"] == 3, "total 是符合条件的总数，不受分页影响"
        assert len(body["items"]) == 1

    def test_search_hits_title_and_content(
        self, api_client: TestClient, session_factory: sessionmaker[Session], author: int
    ):
        with session_factory() as db:
            create_post(db, user_id=author, title="插排不要这样用", content="无关正文")
            create_post(db, user_id=author, title="无关标题", content="这里提到了插排")
            create_post(db, user_id=author, title="完全无关", content="完全无关")

        body = api_client.get(POSTS, params={"keyword": "插排"}).json()

        assert body["total"] == 2

    def test_search_with_no_hits_is_empty_not_an_error(
        self, api_client: TestClient, session_factory: sessionmaker[Session], author: int
    ):
        with session_factory() as db:
            create_post(db, user_id=author)

        body = api_client.get(POSTS, params={"keyword": "绝不可能出现的字符串xyz"}).json()

        assert body["total"] == 0
        assert body["items"] == []

    def test_ties_on_created_at_come_back_newest_id_first(
        self, api_client: TestClient, session_factory: sessionmaker[Session], author: int
    ):
        """同一时刻发布的帖子，按 id 倒序返回。

        帖子是用户随手发的，两条 `created_at` 完全相同很常见
        （知识卡片之间隔着审核，反而不容易撞上）。次序不确定的话，
        翻页会重复或漏项。

        **这条测试证明不了排序里的 `Post.id.desc()` 是必需的。**
        实测过：SQLite 会走 `ix_posts_created_at` 反向扫描，等值项
        天然按 rowid 倒序返回，与显式兜底的结果一致 —— 去掉兜底这条
        依然是绿的。把索引删掉才会变成升序。
        保留它是为了让次序**被规定**，而不是靠某个索引的扫描方向碰巧成立：
        PROJECT_SPEC 里 V2 计划换 PostgreSQL，那里的顺序没有这个巧合。
        这里断言的是对外契约（时间相同则新帖在前），不是兜底本身。
        """
        same_moment = utcnow()
        with session_factory() as db:
            ids = [
                create_post(db, user_id=author, created_at=same_moment).id
                for _ in range(5)
            ]

        got = [item["id"] for item in api_client.get(POSTS).json()["items"]]

        assert got == sorted(ids, reverse=True), "时间相同时应按 id 倒序"

    def test_pagination_does_not_repeat_or_drop_items(
        self, api_client: TestClient, session_factory: sessionmaker[Session], author: int
    ):
        with session_factory() as db:
            for index in range(5):
                create_post(db, user_id=author, title=f"帖子{index}")

        first = api_client.get(POSTS, params={"page": 1, "page_size": 2}).json()
        second = api_client.get(POSTS, params={"page": 2, "page_size": 2}).json()

        ids = [i["id"] for i in first["items"]] + [i["id"] for i in second["items"]]

        assert len(ids) == len(set(ids)), "翻页出现了重复项"

    def test_page_size_over_the_limit_is_rejected(self, api_client: TestClient, author: int):
        assert api_client.get(POSTS, params={"page_size": 101}).status_code == 422


class TestDetail:
    def test_anonymous_can_read_a_post(
        self, api_client: TestClient, session_factory: sessionmaker[Session], author: int
    ):
        with session_factory() as db:
            post = create_post(db, user_id=author, content="完整正文在这里。")

        response = api_client.get(f"{POSTS}/{post.id}")

        assert response.status_code == 200
        assert response.json()["content"] == "完整正文在这里。"

    def test_detail_carries_the_full_content(
        self, api_client: TestClient, session_factory: sessionmaker[Session], author: int
    ):
        long_content = "安全提示。" * 100
        with session_factory() as db:
            post = create_post(db, user_id=author, content=long_content)

        assert api_client.get(f"{POSTS}/{post.id}").json()["content"] == long_content

    def test_missing_post_is_a_readable_404(self, api_client: TestClient):
        response = api_client.get(f"{POSTS}/999999")

        assert response.status_code == 404
        assert response.json()["detail"] == "帖子不存在或已删除"

    def test_hidden_post_is_404_not_403(
        self, api_client: TestClient, session_factory: sessionmaker[Session], author: int
    ):
        """403 等于确认「这里有一条被隐藏的帖子」。"""
        with session_factory() as db:
            post = create_post(db, user_id=author, is_published=False)

        response = api_client.get(f"{POSTS}/{post.id}")

        assert response.status_code == 404
        assert response.json()["detail"] == "帖子不存在或已删除"

    def test_category_name_is_resolved(
        self, api_client: TestClient, session_factory: sessionmaker[Session], author: int
    ):
        with session_factory() as db:
            prepare_categories(db)
            from sqlalchemy import select

            from app.models import Category

            cid = db.scalar(select(Category.id).order_by(Category.id))
            post = create_post(db, user_id=author, category_id=cid)

        body = api_client.get(f"{POSTS}/{post.id}").json()

        assert body["category_id"] == cid
        assert body["category_name"], "分类名要解析出来，否则界面只能显示「未分类」"

    def test_post_without_a_category_is_allowed(
        self, api_client: TestClient, session_factory: sessionmaker[Session], author: int
    ):
        """帖子可以不属于任何分类，此时 category_name 为 null 而不是空串。"""
        with session_factory() as db:
            post = create_post(db, user_id=author, category_id=None)

        body = api_client.get(f"{POSTS}/{post.id}").json()

        assert body["category_id"] is None
        assert body["category_name"] is None

    def test_counts_start_at_zero(
        self, api_client: TestClient, session_factory: sessionmaker[Session], author: int
    ):
        with session_factory() as db:
            post = create_post(db, user_id=author)

        body = api_client.get(f"{POSTS}/{post.id}").json()

        assert body["like_count"] == 0
        assert body["comment_count"] == 0
