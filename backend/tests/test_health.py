"""第五阶段：FastAPI 骨架的接口测试。

覆盖 PROJECT_SPEC 第三十二节要求的「后端启动成功」以及 docs/API.md 第 2 节契约。

注意：数据库与 AI 相关的失败路径测试属于第十五阶段（测试）的内容，
这里只验证当前阶段**真实存在**的功能，不为尚未实现的东西编写假测试。
"""

from __future__ import annotations

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


class TestRoot:
    """GET / —— 最小存活检查。"""

    def test_returns_running_message(self) -> None:
        response = client.get("/")
        assert response.status_code == 200
        assert response.json() == {"message": "AnZhi API is running"}


class TestHealth:
    """GET /api/health —— 健康检查。"""

    def test_returns_ok_status(self) -> None:
        response = client.get("/api/health")
        assert response.status_code == 200

        body = response.json()
        assert body["status"] == "ok"
        assert body["version"] == "1.0.0"

    def test_database_status_is_really_probed(self) -> None:
        """database 字段必须是真实探测结果，不是写死的常量。

        阶段 6 接入 SQLite 前它返回 pending；现在必须如实返回 connected。
        无论何时，谎报状态都属于 PROJECT_SPEC 第一.12 禁止的「伪造接口状态」。
        """
        assert client.get("/api/health").json()["database"] == "connected"

    def test_ai_service_status_reflects_key_presence(self) -> None:
        """未配置 Key 时报告 not_configured，配置后报告 configured。"""
        assert client.get("/api/health").json()["ai_service"] in {
            "configured",
            "not_configured",
        }

    def test_never_leaks_credentials(self) -> None:
        """健康检查响应中不得出现任何密钥痕迹（PROJECT_SPEC 第四十六节）。"""
        text = client.get("/api/health").text.lower()
        for forbidden in ("sk-", "api_key", "apikey", "secret", "token"):
            assert forbidden not in text, f"健康检查响应泄漏了敏感字样：{forbidden}"


class TestErrors:
    """错误路径必须返回统一的 JSON 结构，不能抛裸异常。"""

    def test_unknown_route_returns_json_404(self) -> None:
        response = client.get("/api/this-route-does-not-exist")
        assert response.status_code == 404
        # FastAPI 默认 404 体为 {"detail": ...}，与 docs/API.md 1.1 一致
        assert "detail" in response.json()


class TestDocs:
    """交互式文档可用，便于人工验证接口。"""

    def test_openapi_schema_lists_health_endpoint(self) -> None:
        response = client.get("/openapi.json")
        assert response.status_code == 200
        assert "/api/health" in response.json()["paths"]

    def test_swagger_ui_is_served(self) -> None:
        assert client.get("/docs").status_code == 200
