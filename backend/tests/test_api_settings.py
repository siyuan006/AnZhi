"""个性化设置接口的测试（docs/API.md 第 8 节）。

除了正常的读 / 写，重点守四件事：

 · **没设置过的用户不能拿到 404**：绝大多数人是第一次打开设置页，
   后端必须直接给出默认值，而不是让客户端自己编一套
 · **分区更新的语义**：不传的字段保持原样，传空数组才是「清空」。
   两者混在一起的话，用户永远取消不掉最后一个关注分类
 · **建行时 `home_modules` 必须是「全显示」而不是空数组**：
   列默认值是 `'[]'`，而空数组表示「用户把模块全藏了」——
   只改通知开关的用户会莫名其妙得到一个空首页，且不报任何错
 · **越权**：A 改不了 B 的设置

前三条挂了是功能不可用，第四条挂了是安全事故。
"""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import func, select
from sqlalchemy.orm import Session, sessionmaker

from app.models.user import User
from app.models.user_settings import UserSettings
from app.services.personalization.settings_service import HOME_MODULES
from tests.factories import prepare_categories

SETTINGS = "/api/settings"

GOOD_PASSWORD = "hunter2hunter2"

#: 没写过设置的用户应该看到的默认值
DEFAULT_MODULES = list(HOME_MODULES)


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


def stored_rows(session_factory: sessionmaker[Session]) -> int:
    with session_factory() as db:
        return db.scalar(select(func.count()).select_from(UserSettings)) or 0


def stored_row(
    session_factory: sessionmaker[Session], username: str
) -> UserSettings | None:
    """直接读库里那一行，用来验证「接口返回对了」和「真的存进去了」是两件事。

    按用户名而不是按 id 查：id 是自增的，写死一个数字会让
    「换个顺序注册」这种无关改动把测试搞挂。
    """
    with session_factory() as db:
        return db.scalar(
            select(UserSettings)
            .join(User, User.id == UserSettings.user_id)
            .where(User.username == username)
        )


@pytest.fixture
def token(api_client: TestClient) -> str:
    return register(api_client, "alice")


@pytest.fixture
def categories(session_factory: sessionmaker[Session]) -> None:
    """六大分类必须存在，否则关注任何分类都会被判「分类不存在」。"""
    with session_factory() as db:
        prepare_categories(db)


class TestAuthIsRequired:
    """设置是跟着账号走的，没有账号就没有「我的设置」。"""

    def test_reading_without_a_token_is_a_401(self, api_client: TestClient):
        response = api_client.get(SETTINGS)

        assert response.status_code == 401
        assert response.json()["detail"] == "请先登录"

    def test_updating_without_a_token_is_a_401(self, api_client: TestClient):
        response = api_client.put(SETTINGS, json={"notify_enabled": False})

        assert response.status_code == 401


class TestDefaults:
    """从没打开过设置页的用户。"""

    def test_first_read_returns_defaults_not_a_404(
        self, api_client: TestClient, token: str
    ):
        response = api_client.get(SETTINGS, headers=auth_header(token))

        assert response.status_code == 200, response.text
        assert response.json() == {
            "followed_categories": [],
            "home_modules": DEFAULT_MODULES,
            "notify_enabled": True,
        }

    def test_reading_does_not_create_a_row(
        self,
        api_client: TestClient,
        token: str,
        session_factory: sessionmaker[Session],
    ):
        """GET 不该有副作用。

        它会被首页每次加载调用，为一个只读请求插一行纯属浪费；
        而且一旦写坏了，用户会在自己完全没操作过的情况下
        拥有一份「被设置过」的记录。
        """
        api_client.get(SETTINGS, headers=auth_header(token))
        api_client.get(SETTINGS, headers=auth_header(token))

        assert stored_rows(session_factory) == 0

    def test_first_write_keeps_every_module_visible(
        self,
        api_client: TestClient,
        token: str,
        session_factory: sessionmaker[Session],
    ):
        """只改通知开关，不该顺手把首页清空。

        `home_modules` 列的 server_default 是 `'[]'`，
        而空数组在本模块里表示「用户把所有模块都藏起来了」。
        建行时不显式填默认值的话，这次 PUT 的响应看着完全正常
        （`home_modules` 是默认全量），但库里那一行是空的 ——
        要等用户下次进来才发现首页空了，且查不出是谁改的。
        """
        response = api_client.put(
            SETTINGS, json={"notify_enabled": False}, headers=auth_header(token)
        )

        assert response.status_code == 200, response.text
        assert response.json()["home_modules"] == DEFAULT_MODULES

        row = stored_row(session_factory, "alice")
        assert row is not None, "第一次写就该建行"
        assert row.home_modules == DEFAULT_MODULES, (
            "库里那一行也必须是全量模块 —— 响应对不代表存对了"
        )

    def test_reading_after_a_write_returns_what_was_saved(
        self, api_client: TestClient, token: str
    ):
        """写完之后再 GET，拿到的必须是刚存的那份。"""
        api_client.put(
            SETTINGS, json={"notify_enabled": False}, headers=auth_header(token)
        )

        response = api_client.get(SETTINGS, headers=auth_header(token))

        assert response.json() == {
            "followed_categories": [],
            "home_modules": DEFAULT_MODULES,
            "notify_enabled": False,
        }


class TestPartialUpdate:
    """没传的字段保持原样 —— 这是 PUT 在这个接口上的核心约定。"""

    def test_an_empty_body_changes_nothing(
        self, api_client: TestClient, token: str, categories: None
    ):
        api_client.put(
            SETTINGS,
            json={"followed_categories": [1], "notify_enabled": False},
            headers=auth_header(token),
        )

        response = api_client.put(SETTINGS, json={}, headers=auth_header(token))

        assert response.status_code == 200, response.text
        assert response.json() == {
            "followed_categories": [1],
            "home_modules": DEFAULT_MODULES,
            "notify_enabled": False,
        }

    def test_an_explicit_null_also_means_leave_it_alone(
        self, api_client: TestClient, token: str
    ):
        api_client.put(
            SETTINGS, json={"notify_enabled": False}, headers=auth_header(token)
        )

        response = api_client.put(
            SETTINGS, json={"notify_enabled": None}, headers=auth_header(token)
        )

        assert response.json()["notify_enabled"] is False, (
            "显式传 null 与不传等价：都是「这次不改这一项」"
        )

    def test_an_empty_list_really_does_clear(
        self, api_client: TestClient, token: str, categories: None
    ):
        """空数组与不传必须区分得开。

        它们混为一谈的话，用户取消掉最后一个关注分类之后，
        下次保存别的开关又会把它加回来 —— 而且界面显示「已保存」。
        """
        api_client.put(
            SETTINGS, json={"followed_categories": [1, 2]}, headers=auth_header(token)
        )

        response = api_client.put(
            SETTINGS, json={"followed_categories": []}, headers=auth_header(token)
        )

        assert response.json()["followed_categories"] == []

    def test_hiding_every_module_is_remembered_as_empty(
        self, api_client: TestClient, token: str
    ):
        """反过来也一样：全藏起来要能存住，不能又被当成「没设置过」。"""
        api_client.put(SETTINGS, json={"home_modules": []}, headers=auth_header(token))

        response = api_client.get(SETTINGS, headers=auth_header(token))

        assert response.json()["home_modules"] == []


class TestNormalization:
    """同样的选择只有一种存法。"""

    def test_categories_are_deduplicated_and_sorted(
        self, api_client: TestClient, token: str, categories: None
    ):
        response = api_client.put(
            SETTINGS,
            json={"followed_categories": [3, 1, 3, 2]},
            headers=auth_header(token),
        )

        assert response.json()["followed_categories"] == [1, 2, 3]

    def test_modules_follow_the_home_page_order(
        self, api_client: TestClient, token: str
    ):
        """模块数组的顺序不承载信息，固定成首页从上到下的顺序。

        用 `sorted()` 会得到字母序（ai / category / community / …），
        与首页的排布毫无关系，前端拿着它也没法直接渲染。
        """
        response = api_client.put(
            SETTINGS,
            json={"home_modules": ["community", "ai", "daily", "ai"]},
            headers=auth_header(token),
        )

        assert response.json()["home_modules"] == ["daily", "ai", "community"]


class TestValidation:
    def test_an_unknown_category_is_a_404(
        self, api_client: TestClient, token: str, categories: None
    ):
        """分类是对一个已存在资源的引用，引用不存在就是 404 ——
        与 `POST /api/posts` 对分类的处理保持一致。"""
        response = api_client.put(
            SETTINGS,
            json={"followed_categories": [1, 999]},
            headers=auth_header(token),
        )

        assert response.status_code == 404
        assert "999" in response.json()["detail"], (
            "detail 要点出是哪个 id 不对：五项数组只回一句「参数不对」，"
            "客户端无从下手"
        )

    def test_a_bad_category_does_not_get_saved(
        self,
        api_client: TestClient,
        token: str,
        categories: None,
        session_factory: sessionmaker[Session],
    ):
        """校验失败必须是「整条请求都不生效」，不能把合法的那部分存进去。"""
        api_client.put(
            SETTINGS, json={"followed_categories": [1, 999]}, headers=auth_header(token)
        )

        assert stored_rows(session_factory) == 0

    def test_an_unknown_module_is_a_422(self, api_client: TestClient, token: str):
        """模块键是请求体里的一个枚举值，写错了是该请求本身不合法。"""
        response = api_client.put(
            SETTINGS,
            json={"home_modules": ["daily", "weather"]},
            headers=auth_header(token),
        )

        assert response.status_code == 422
        assert "weather" in response.json()["detail"]

    @pytest.mark.parametrize("value", ["abc", 1.5, [1, "2"]])
    def test_a_non_integer_category_is_rejected(
        self, api_client: TestClient, token: str, value: object
    ):
        response = api_client.put(
            SETTINGS, json={"followed_categories": [value]}, headers=auth_header(token)
        )

        assert response.status_code == 422

    def test_too_many_categories_are_rejected(
        self, api_client: TestClient, token: str, categories: None
    ):
        """上限是给异常客户端兜底的。

        不限长的话，几万项会被原样拼进 `IN (...)`，
        轻则慢查询，重则撞上数据库的参数个数上限变成 500。
        """
        response = api_client.put(
            SETTINGS,
            json={"followed_categories": list(range(1, 402))},
            headers=auth_header(token),
        )

        assert response.status_code == 422


class TestIsolation:
    def test_one_users_settings_do_not_leak_into_anothers(
        self, api_client: TestClient, session_factory: sessionmaker[Session]
    ):
        """设置是私有的，而且必须各存各的一行。"""
        alice = register(api_client, "alice")
        bob = register(api_client, "bob")

        api_client.put(
            SETTINGS, json={"notify_enabled": False}, headers=auth_header(alice)
        )

        response = api_client.get(SETTINGS, headers=auth_header(bob))

        assert response.json()["notify_enabled"] is True, (
            "bob 没设置过，拿到的应该是默认值"
        )
        assert stored_rows(session_factory) == 1, "只有 alice 那一行"


class TestPersistence:
    def test_the_row_really_holds_the_new_values(
        self,
        api_client: TestClient,
        token: str,
        categories: None,
        session_factory: sessionmaker[Session],
    ):
        """直接验库里的那一行。

        JSON 数组字段在 SQLAlchemy 里有个典型的坑：不套 MutableList 时
        原地修改**不会**被写进数据库，而且不报任何错 ——
        接口读的是同一个会话里的对象，看着一切正常，
        重新打开 App 才发现改动没了。这里绕开接口直接回表，
        就是为了让那种「响应对、数据没存上」的情况无处可藏。
        """
        api_client.put(
            SETTINGS,
            json={
                "followed_categories": [1, 2],
                "home_modules": ["ai"],
                "notify_enabled": False,
            },
            headers=auth_header(token),
        )

        row = stored_row(session_factory, "alice")
        assert row is not None
        assert row.followed_categories == [1, 2]
        assert row.home_modules == ["ai"]
        assert row.notify_enabled is False
