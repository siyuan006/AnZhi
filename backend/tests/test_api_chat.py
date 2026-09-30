"""阶段 8：`POST /api/chat` 接口。

用 `app.dependency_overrides` 把 ChatService 换成注入了假上游的实现，
因此测的是**真实的 FastAPI 应用**（路由、校验、异常处理都是真的），
只有最外层的 DeepSeek 被换掉。
"""

from __future__ import annotations

import json

import httpx
import pytest
from fastapi.testclient import TestClient

from app.api.chat import get_chat_service
from app.main import app
from app.services.ai.chat_service import ChatService
from app.services.ai.deepseek_client import DeepSeekClient


def _service(handler) -> ChatService:
    client = DeepSeekClient(api_key="sk-test", transport=httpx.MockTransport(handler))
    return ChatService(client)


def _upstream(payload: dict | str, status: int = 200) -> ChatService:
    content = payload if isinstance(payload, str) else json.dumps(payload)

    def handler(request: httpx.Request) -> httpx.Response:
        if status != 200:
            return httpx.Response(status, json={"error": "x"})
        return httpx.Response(200, json={"choices": [{"message": {"content": content}}]})

    return _service(handler)


@pytest.fixture
def chat_client() -> TestClient:
    """不覆盖依赖的客户端，用于测「未配置」这一真实默认状态。"""

    def _unconfigured() -> ChatService:
        return ChatService(DeepSeekClient(api_key=""))

    app.dependency_overrides[get_chat_service] = _unconfigured
    with TestClient(app) as client:
        yield client
    app.dependency_overrides.clear()


def _client_with(service: ChatService) -> TestClient:
    app.dependency_overrides[get_chat_service] = lambda: service
    return TestClient(app)


class TestRequestValidation:
    """请求校验必须拦住无效输入，不能白白消耗一次 API 调用。"""

    def test_empty_message_is_rejected(self, chat_client: TestClient) -> None:
        assert chat_client.post("/api/chat", json={"message": ""}).status_code == 422

    def test_whitespace_only_message_is_rejected(self, chat_client: TestClient) -> None:
        assert chat_client.post("/api/chat", json={"message": "   "}).status_code == 422

    def test_missing_message_is_rejected(self, chat_client: TestClient) -> None:
        assert chat_client.post("/api/chat", json={}).status_code == 422

    def test_overlong_message_is_rejected(self, chat_client: TestClient) -> None:
        response = chat_client.post("/api/chat", json={"message": "问" * 1001})
        assert response.status_code == 422

    def test_too_many_history_items_are_rejected(self, chat_client: TestClient) -> None:
        response = chat_client.post(
            "/api/chat",
            json={"message": "问题", "history": ["问"] * 7},
        )
        assert response.status_code == 422

    def test_validation_error_has_readable_detail(self, chat_client: TestClient) -> None:
        body = chat_client.post("/api/chat", json={"message": ""}).json()
        assert "detail" in body
        assert body.get("errors")


class TestUnconfigured:
    def test_returns_503_with_actionable_message(self, chat_client: TestClient) -> None:
        response = chat_client.post("/api/chat", json={"message": "宿舍着火怎么办"})

        # 503 而不是 500：这是部署配置问题，不是服务器崩溃
        assert response.status_code == 503
        detail = response.json()["detail"]
        assert "DEEPSEEK_API_KEY" in detail
        # 提示必须给出可执行的下一步，而不是只说「出错了」
        assert "backend/.env" in detail


class TestSuccess:
    def test_returns_structured_answer(self) -> None:
        service = _upstream(
            {
                "category": "消防安全",
                "risk_level": "high",
                "answer": "立即撤离，不要返回取物。",
                "steps": ["叫醒室友", "低姿撤离", "拨打 119"],
                "sources": [],
                "warning": "生命安全优先。",
            }
        )
        with _client_with(service) as client:
            response = client.post("/api/chat", json={"message": "宿舍着火怎么办"})

        assert response.status_code == 200
        body = response.json()
        # 字段与 PROJECT_SPEC 第九节的回答结构一一对应
        assert set(body) == {
            "question",
            "category",
            "risk_level",
            "answer",
            "steps",
            "sources",
            "warning",
        }
        assert body["question"] == "宿舍着火怎么办"
        assert body["risk_level"] == "high"
        assert body["steps"] == ["叫醒室友", "低姿撤离", "拨打 119"]

    def test_category_can_be_specified(self) -> None:
        captured: dict = {}

        def handler(request: httpx.Request) -> httpx.Response:
            captured["body"] = json.loads(request.content)
            return httpx.Response(
                200, json={"choices": [{"message": {"content": '{"answer": "x"}'}}]}
            )

        with _client_with(_service(handler)) as client:
            response = client.post(
                "/api/chat",
                json={"message": "插座冒烟怎么办", "category": "用电安全"},
            )

        assert response.status_code == 200
        assert "用电安全" in captured["body"]["messages"][1]["content"]


class TestUpstreamFailure:
    @pytest.mark.parametrize(
        ("status", "expected"),
        [(401, 503), (429, 503), (500, 502), (400, 502)],
    )
    def test_upstream_status_is_translated(self, status: int, expected: int) -> None:
        with _client_with(_upstream({"answer": "x"}, status=status)) as client:
            response = client.post("/api/chat", json={"message": "问题"})

        assert response.status_code == expected
        # 错误响应必须是统一结构，前端只需要实现一套解析
        assert "detail" in response.json()

    def test_timeout_becomes_504(self) -> None:
        def handler(request: httpx.Request) -> httpx.Response:
            raise httpx.ReadTimeout("slow", request=request)

        with _client_with(_service(handler)) as client:
            response = client.post("/api/chat", json={"message": "问题"})

        assert response.status_code == 504

    def test_unparsable_model_output_becomes_502(self) -> None:
        with _client_with(_upstream("我今天不想输出 JSON")) as client:
            response = client.post("/api/chat", json={"message": "问题"})

        assert response.status_code == 502
        assert "格式" in response.json()["detail"]

    def test_upstream_error_body_is_not_leaked_to_client(self) -> None:
        service = _upstream({"answer": "x"}, status=500)
        with _client_with(service) as client:
            response = client.post("/api/chat", json={"message": "问题"})

        # 上游的原始响应片段只应留在服务端日志里
        assert "error" not in response.text
        assert response.json()["detail"] == "AI 服务暂时不可用，请稍后重试"


class TestSafetyGuardIsWiredIn:
    """阶段 9：审查层必须真的在响应链路上。

    `test_safety_guard.py` 已经把规则本身测透了，但那些测试
    直接调用 SafetyGuard，**证明不了它被 ChatService 调用过**。
    一个存在却没人调用的审查层，和不存在没有区别 ——
    这一组用例守的就是这条接线。
    """

    def test_dangerous_upstream_answer_does_not_reach_the_client(self) -> None:
        service = _upstream(
            {
                "risk_level": "high",
                "answer": "火势不大时，可以返回火场取回重要证件。",
                "steps": ["返回火场取证件", "拨打 119"],
                "sources": ["《消防法》"],
                "warning": "注意安全。",
            }
        )
        with _client_with(service) as client:
            body = client.post("/api/chat", json={"message": "宿舍发生火灾怎么办"}).json()

        assert "返回火场" not in body["answer"]
        assert body["steps"] == []
        assert body["risk_level"] == "high"
        # 拦下之后要告诉用户该做什么，而不是只留一句「已被拦下」
        for number in ("119", "120", "110"):
            assert number in body["warning"]

    def test_risk_level_judged_too_low_is_raised_in_the_response(self) -> None:
        service = _upstream({"answer": "先切断电源。", "risk_level": "low"})
        with _client_with(service) as client:
            body = client.post("/api/chat", json={"message": "室友触电了怎么办"}).json()

        assert body["risk_level"] == "high"
        assert body["warning"]

    def test_correct_negated_advice_survives_the_whole_path(self) -> None:
        """「切勿返回火场」是正确的回答，必须原样送到用户手里。"""
        service = _upstream(
            {
                "risk_level": "high",
                "answer": "立即撤离，切勿返回火场取物。",
                "steps": ["叫醒室友", "低姿撤离", "拨打 119"],
                "warning": "生命安全优先，立即拨打 119。",
            }
        )
        with _client_with(service) as client:
            body = client.post("/api/chat", json={"message": "宿舍发生火灾怎么办"}).json()

        assert body["answer"] == "立即撤离，切勿返回火场取物。"
        assert len(body["steps"]) == 3
