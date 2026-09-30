"""认证接口的测试（docs/API.md 第 11 节）。

除了正常的注册 / 登录，重点守三件事：
 · 响应体里**绝不能出现 password_hash**
 · 用户名不存在与密码错误**不能给出不同的提示**
 · 未登录访问受保护接口要拿到 401 而不是 500
"""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient
from sqlalchemy.orm import Session, sessionmaker

from app.services.auth import auth_service

REGISTER = "/api/auth/register"
LOGIN = "/api/auth/login"
ME = "/api/auth/me"

GOOD_PASSWORD = "hunter2hunter2"


def register(client: TestClient, username: str = "xiaoming", **extra: object):
    payload = {"username": username, "password": GOOD_PASSWORD}
    payload.update(extra)
    return client.post(REGISTER, json=payload)


def auth_header(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


class TestRegister:
    def test_returns_a_token_and_the_user(self, api_client: TestClient):
        response = register(api_client)

        assert response.status_code == 201
        body = response.json()
        assert body["access_token"]
        assert body["token_type"] == "bearer"
        assert body["expires_in"] > 0
        assert body["user"]["username"] == "xiaoming"
        assert body["user"]["id"] > 0

    def test_response_never_contains_the_password(self, api_client: TestClient):
        """整个响应里不允许出现口令或它的哈希。

        这条挂了的后果不是功能坏掉，而是**用户密码泄露** ——
        一个把响应整个记进日志的客户端就足以造成事故。
        """
        raw = register(api_client).text

        assert GOOD_PASSWORD not in raw
        assert "password" not in raw.lower()
        assert "$2b$" not in raw

    def test_duplicate_username_is_a_409(self, api_client: TestClient):
        register(api_client)

        response = register(api_client)

        assert response.status_code == 409
        assert response.json()["detail"] == "该用户名已被注册"

    def test_short_password_is_a_400_with_a_readable_reason(
        self, api_client: TestClient
    ):
        response = register(api_client, password="abc")

        assert response.status_code == 400
        assert "8" in response.json()["detail"]

    def test_over_long_chinese_password_is_a_400_not_a_500(
        self, api_client: TestClient
    ):
        """25 个汉字 = 75 字节，超过 bcrypt 的上限。

        不显式校验的话，bcrypt 会抛 ValueError 一路冒成 500，
        用户只看到「服务器错误」，完全不知道是密码太长。
        """
        response = register(api_client, password="安" * 25)

        assert response.status_code == 400
        assert "汉字" in response.json()["detail"]

    def test_short_username_is_rejected(self, api_client: TestClient):
        response = register(api_client, username="ab")

        assert response.status_code == 400

    def test_nickname_is_saved(self, api_client: TestClient):
        response = register(api_client, nickname="小明")

        assert response.json()["user"]["nickname"] == "小明"

    def test_username_is_trimmed(self, api_client: TestClient, session_factory):
        response = register(api_client, username="  xiaoming  ")

        assert response.json()["user"]["username"] == "xiaoming"

    def test_registered_user_is_actually_persisted(
        self, api_client: TestClient, session_factory: sessionmaker[Session]
    ):
        """不能只信响应体 —— 回数据库确认真的写进去了。"""
        register(api_client)

        with session_factory() as db:
            user = auth_service.get_user_by_username(db, "xiaoming")
            assert user is not None
            assert user.password_hash.startswith("$2b$")
            assert user.password_hash != GOOD_PASSWORD

    def test_returned_token_works_immediately(self, api_client: TestClient):
        """注册完直接拿着 token 就能用，不必再登录一次。"""
        token = register(api_client).json()["access_token"]

        assert api_client.get(ME, headers=auth_header(token)).status_code == 200


class TestLogin:
    @pytest.fixture
    def registered(self, api_client: TestClient) -> TestClient:
        register(api_client)
        return api_client

    def test_correct_password_returns_a_token(self, registered: TestClient):
        response = registered.post(
            LOGIN, json={"username": "xiaoming", "password": GOOD_PASSWORD}
        )

        assert response.status_code == 200
        assert response.json()["access_token"]

    def test_wrong_password_is_a_401(self, registered: TestClient):
        response = registered.post(
            LOGIN, json={"username": "xiaoming", "password": "wrongwrong"}
        )

        assert response.status_code == 401

    def test_unknown_username_gives_the_same_message_as_a_wrong_password(
        self, registered: TestClient
    ):
        """两种失败必须是同一句话。

        分开提示（「用户不存在」/「密码错误」）等于对外提供了一个
        「这个用户名注册过没有」的查询接口，可以被用来枚举用户。
        """
        wrong_password = registered.post(
            LOGIN, json={"username": "xiaoming", "password": "wrongwrong"}
        )
        unknown_user = registered.post(
            LOGIN, json={"username": "nobody", "password": GOOD_PASSWORD}
        )

        assert wrong_password.status_code == unknown_user.status_code == 401
        assert wrong_password.json()["detail"] == unknown_user.json()["detail"]

    def test_password_is_case_sensitive(self, registered: TestClient):
        response = registered.post(
            LOGIN, json={"username": "xiaoming", "password": GOOD_PASSWORD.upper()}
        )

        assert response.status_code == 401

    def test_login_does_not_accept_a_hash_as_the_password(
        self, registered: TestClient, session_factory: sessionmaker[Session]
    ):
        """拿着数据库里的哈希当密码登录必须失败。

        这条守的是「口令比对没被写成字符串相等」——
        一旦有人图省事写成 `hash == hash`，这里就会通过。
        """
        with session_factory() as db:
            user = auth_service.get_user_by_username(db, "xiaoming")
            assert user is not None
            stolen_hash = user.password_hash

        response = registered.post(
            LOGIN, json={"username": "xiaoming", "password": stolen_hash}
        )

        assert response.status_code == 401


class TestMe:
    def test_returns_the_current_user(self, api_client: TestClient):
        token = register(api_client).json()["access_token"]

        response = api_client.get(ME, headers=auth_header(token))

        assert response.status_code == 200
        assert response.json()["username"] == "xiaoming"

    def test_without_a_token_is_a_401(self, api_client: TestClient):
        response = api_client.get(ME)

        assert response.status_code == 401
        assert response.json()["detail"] == "请先登录"

    def test_with_a_garbage_token_is_a_401(self, api_client: TestClient):
        response = api_client.get(ME, headers=auth_header("not-a-token"))

        assert response.status_code == 401

    def test_token_of_a_deleted_user_is_a_401(
        self, api_client: TestClient, session_factory: sessionmaker[Session]
    ):
        """用户被删掉后，旧 token 在过期前签名依然有效。

        不回数据库确认的话，一个已注销的账号还能继续访问 ——
        这是「注销」这个功能最容易做假的地方。
        """
        token = register(api_client).json()["access_token"]

        with session_factory() as db:
            user = auth_service.get_user_by_username(db, "xiaoming")
            assert user is not None
            db.delete(user)
            db.commit()

        assert api_client.get(ME, headers=auth_header(token)).status_code == 401

    def test_me_does_not_leak_the_password_hash(self, api_client: TestClient):
        token = register(api_client).json()["access_token"]

        raw = api_client.get(ME, headers=auth_header(token)).text

        assert "$2b$" not in raw
        assert "password" not in raw.lower()


class TestAuthIsNotRequiredForPublicContent:
    """登录墙只能挡在需要身份的功能前面。

    安知是安全科普应用，用户可能在起火、有人触电的当口打开它 ——
    任何一道多余的登录墙都在延误他拿到处置方法。
    """

    @pytest.mark.parametrize(
        "path",
        ["/api/health", "/api/categories", "/api/knowledge"],
    )
    def test_public_endpoints_stay_open(self, api_client: TestClient, path: str):
        assert api_client.get(path).status_code == 200
