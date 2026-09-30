"""统一错误结构契约。

`docs/API.md` 1.1 承诺「任何出错路径都返回统一结构」，客户端据此只实现一套
错误解析逻辑。这组测试守住这个承诺 —— 它是前后端之间最容易被破坏的约定，
因为后端改一处响应结构，客户端往往要等到线上才报错。
"""

from __future__ import annotations

import json

from fastapi.testclient import TestClient

from app.main import app


def _client() -> TestClient:
    return TestClient(app)


class TestValidationError:
    """422 由自定义校验器触发时最容易出问题。"""

    def test_custom_validator_error_is_serializable(self) -> None:
        """自定义校验器抛 ValueError 时，pydantic 会把异常对象放进 ctx。

        如果直接把 `exc.errors()` 塞进响应体，本该是 422 的请求会变成 500。
        """
        with _client() as client:
            response = client.post("/api/chat", json={"message": "   "})

        assert response.status_code == 422
        # 能走到这一步就说明响应体是可序列化的
        json.dumps(response.json())

    def test_errors_entries_follow_the_documented_shape(self) -> None:
        """客户端读的是 errors[0].message，字段名不能变。"""
        with _client() as client:
            body = client.post("/api/chat", json={"message": ""}).json()

        assert isinstance(body["errors"], list)
        first = body["errors"][0]
        assert set(first) == {"field", "message", "type"}
        assert isinstance(first["message"], str) and first["message"]

    def test_message_has_no_internal_prefix(self) -> None:
        """pydantic 会加上「Value error, 」这类内部前缀，不该出现在用户看到的文案里。"""
        with _client() as client:
            body = client.post("/api/chat", json={"message": "   "}).json()

        message = body["errors"][0]["message"]
        assert "Value error" not in message
        assert message == "问题不能为空"

    def test_detail_is_a_readable_sentence(self) -> None:
        with _client() as client:
            body = client.post("/api/chat", json={"message": ""}).json()

        assert body["detail"].startswith("参数校验失败：")
        assert "message" in body["detail"]

    def test_does_not_leak_user_input(self) -> None:
        """超长输入不应被原样回显到错误里。"""
        secret = "x" * 2000
        with _client() as client:
            response = client.post("/api/chat", json={"message": secret})

        assert response.status_code == 422
        assert secret not in response.text

    def test_missing_body_is_handled(self) -> None:
        with _client() as client:
            response = client.post("/api/chat", json={})

        assert response.status_code == 422
        assert response.json()["errors"][0]["field"] == "message"


class TestOtherErrors:
    def test_not_found_uses_detail(self) -> None:
        with _client() as client:
            response = client.get("/api/knowledge/999999")

        assert response.status_code == 404
        assert set(response.json()) == {"detail"}
        assert response.json()["detail"] == "知识不存在或未发布"

    def test_unknown_route_returns_json_not_html(self) -> None:
        with _client() as client:
            response = client.get("/api/definitely-not-a-route")

        assert response.status_code == 404
        assert response.headers["content-type"].startswith("application/json")

    def test_internal_error_hides_stack_trace(self) -> None:
        """兜底处理器必须把堆栈留在服务端。"""

        @app.get("/api/_boom", include_in_schema=False)
        async def _boom() -> None:  # pragma: no cover - 仅用于触发
            raise RuntimeError("数据库连接串泄露警告：secret-token")

        try:
            # TestClient 默认会把服务端异常重新抛出，这里关掉才能拿到响应
            with TestClient(app, raise_server_exceptions=False) as client:
                response = client.get("/api/_boom")

            assert response.status_code == 500
            assert response.json() == {"detail": "服务器内部错误"}
            assert "secret-token" not in response.text
            assert "RuntimeError" not in response.text
        finally:
            app.router.routes = [
                route for route in app.router.routes if getattr(route, "path", "") != "/api/_boom"
            ]
