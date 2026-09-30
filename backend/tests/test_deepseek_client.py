"""阶段 8：DeepSeek 客户端。

全部测试都通过 `httpx.MockTransport` 拦截请求：
**不联网、不使用真实 Key、不消耗额度**，但走完真实的请求构造与解析路径。
"""

from __future__ import annotations

import asyncio
import json
import logging

import httpx
import pytest

from app.services.ai.deepseek_client import DeepSeekClient
from app.services.ai.errors import AIFailure, AIServiceError

FAKE_KEY = "sk-fake-key-for-testing-0123456789"


def _completion(content: str, status: int = 200) -> httpx.Response:
    """构造一个形如 DeepSeek 的成功响应。"""
    if status != 200:
        return httpx.Response(status, json={"error": {"message": "boom"}})
    return httpx.Response(
        status,
        json={"choices": [{"message": {"role": "assistant", "content": content}}]},
    )


def _client(handler, **kwargs) -> DeepSeekClient:
    """构造注入了假 transport 的客户端。"""
    return DeepSeekClient(
        api_key=kwargs.pop("api_key", FAKE_KEY),
        transport=httpx.MockTransport(handler),
        **kwargs,
    )


def _run(coro):
    return asyncio.run(coro)


class TestConfiguration:
    def test_missing_key_raises_not_configured_without_any_request(self) -> None:
        called = False

        def handler(request: httpx.Request) -> httpx.Response:  # pragma: no cover
            nonlocal called
            called = True
            return _completion("{}")

        client = _client(handler, api_key="")

        with pytest.raises(AIServiceError) as exc:
            _run(client.complete_json("宿舍着火怎么办"))

        assert exc.value.reason is AIFailure.NOT_CONFIGURED
        # 没配 Key 就绝不该发出请求
        assert called is False

    def test_is_configured_reflects_key_presence(self) -> None:
        assert _client(lambda r: _completion("{}")).is_configured is True
        assert _client(lambda r: _completion("{}"), api_key="").is_configured is False


class TestRequestShape:
    def test_sends_expected_payload_and_auth_header(self) -> None:
        captured: dict = {}

        def handler(request: httpx.Request) -> httpx.Response:
            captured["url"] = str(request.url)
            captured["auth"] = request.headers.get("authorization")
            captured["body"] = json.loads(request.content)
            return _completion('{"answer": "ok", "risk_level": "low"}')

        client = _client(handler, base_url="https://api.deepseek.com", model="deepseek-chat")
        result = _run(client.complete_json("宿舍着火怎么办"))

        assert result["answer"] == "ok"
        assert captured["url"] == "https://api.deepseek.com/chat/completions"
        assert captured["auth"] == f"Bearer {FAKE_KEY}"

        body = captured["body"]
        assert body["model"] == "deepseek-chat"
        assert body["stream"] is False
        # 要求上游直接返回 JSON，避免脆弱的文本抠取
        assert body["response_format"] == {"type": "json_object"}
        # 安全领域的回答不该有高随机性
        assert 0 <= body["temperature"] <= 0.5
        assert body["messages"][0]["role"] == "system"
        assert body["messages"][1]["content"].endswith("宿舍着火怎么办")

    def test_category_is_passed_into_prompt(self) -> None:
        captured: dict = {}

        def handler(request: httpx.Request) -> httpx.Response:
            captured["body"] = json.loads(request.content)
            return _completion('{"answer": "ok"}')

        _run(_client(handler).complete_json("插座冒烟怎么办", category="用电安全"))

        assert "用电安全" in captured["body"]["messages"][1]["content"]


class TestParsing:
    def test_plain_json(self) -> None:
        result = _run(
            _client(lambda r: _completion('{"answer": "先断电", "risk_level": "high"}'))
            .complete_json("插座冒烟")
        )
        assert result["answer"] == "先断电"

    def test_tolerates_markdown_code_fence(self) -> None:
        """模型偶尔会无视 JSON 模式包一层代码块，不该让用户为此重问一次。"""
        fenced = '```json\n{"answer": "先断电", "risk_level": "high"}\n```'
        result = _run(_client(lambda r: _completion(fenced)).complete_json("插座冒烟"))
        assert result["answer"] == "先断电"

    def test_invalid_json_is_reported_as_bad_response(self) -> None:
        with pytest.raises(AIServiceError) as exc:
            _run(_client(lambda r: _completion("我觉得应该先断电")).complete_json("插座冒烟"))
        assert exc.value.reason is AIFailure.BAD_RESPONSE

    def test_json_array_is_rejected(self) -> None:
        """顶层是数组同样不可用，我们的契约是对象。"""
        with pytest.raises(AIServiceError) as exc:
            _run(_client(lambda r: _completion("[1, 2, 3]")).complete_json("插座冒烟"))
        assert exc.value.reason is AIFailure.BAD_RESPONSE

    def test_empty_content_is_rejected(self) -> None:
        with pytest.raises(AIServiceError) as exc:
            _run(_client(lambda r: _completion("   ")).complete_json("插座冒烟"))
        assert exc.value.reason is AIFailure.BAD_RESPONSE

    def test_unexpected_structure_is_rejected(self) -> None:
        def handler(request: httpx.Request) -> httpx.Response:
            return httpx.Response(200, json={"unexpected": True})

        with pytest.raises(AIServiceError) as exc:
            _run(_client(handler).complete_json("插座冒烟"))
        assert exc.value.reason is AIFailure.UPSTREAM_ERROR


class TestFailureMapping:
    @pytest.mark.parametrize(
        ("status", "reason"),
        [
            (401, AIFailure.UNAUTHORIZED),
            (403, AIFailure.UNAUTHORIZED),
            (429, AIFailure.RATE_LIMITED),
            (500, AIFailure.UPSTREAM_ERROR),
            (503, AIFailure.UPSTREAM_ERROR),
            (400, AIFailure.UPSTREAM_ERROR),
        ],
    )
    def test_http_status_is_mapped(self, status: int, reason: AIFailure) -> None:
        with pytest.raises(AIServiceError) as exc:
            _run(
                _client(lambda r: httpx.Response(status, json={"error": "x"}))
                .complete_json("插座冒烟")
            )
        assert exc.value.reason is reason

    def test_timeout_is_mapped(self) -> None:
        def handler(request: httpx.Request) -> httpx.Response:
            raise httpx.ReadTimeout("too slow", request=request)

        with pytest.raises(AIServiceError) as exc:
            _run(_client(handler).complete_json("插座冒烟"))
        assert exc.value.reason is AIFailure.TIMEOUT
        assert "超时" in exc.value.message

    def test_connection_error_is_mapped(self) -> None:
        def handler(request: httpx.Request) -> httpx.Response:
            raise httpx.ConnectError("no route", request=request)

        with pytest.raises(AIServiceError) as exc:
            _run(_client(handler).complete_json("插座冒烟"))
        assert exc.value.reason is AIFailure.UPSTREAM_ERROR


class TestKeyNeverLeaks:
    """API Key 绝不能出现在任何面向用户或面向日志的文本里。

    这是硬性要求（PROJECT_SPEC 第三十五节），因此单独测：
    「代码里没写 Key」不等于「运行时不会把 Key 打出来」。
    """

    def test_error_messages_never_contain_the_key(self, caplog) -> None:
        def handler(request: httpx.Request) -> httpx.Response:
            return httpx.Response(401, json={"error": {"message": "invalid key"}})

        with caplog.at_level(logging.DEBUG):
            with pytest.raises(AIServiceError) as exc:
                _run(_client(handler).complete_json("插座冒烟"))

        assert FAKE_KEY not in exc.value.message
        assert FAKE_KEY not in str(exc.value)
        for record in caplog.records:
            assert FAKE_KEY not in record.getMessage()

    def test_error_messages_never_contain_the_key_on_malformed_response(self, caplog) -> None:
        with caplog.at_level(logging.DEBUG):
            with pytest.raises(AIServiceError) as exc:
                _run(_client(lambda r: _completion("not json")).complete_json("插座冒烟"))

        assert FAKE_KEY not in str(exc.value)
        for record in caplog.records:
            assert FAKE_KEY not in record.getMessage()
