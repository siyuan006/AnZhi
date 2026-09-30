"""阶段 8：问答编排与回答规范化。

模型的输出不保证符合契约。这一组测试覆盖「模型不听话时会发生什么」——
这些分支在真实调用里很难复现，恰恰是最需要被测到的部分。
"""

from __future__ import annotations

import asyncio
import json

import httpx
import pytest

from app.schemas.chat import ChatResponse
from app.services.ai.chat_service import ChatService
from app.services.ai.deepseek_client import DeepSeekClient
from app.services.ai.errors import AIFailure, AIServiceError
from app.services.ai.rag_service import RAGService, RetrievedCard
from app.services.ai.safety_guard import EMERGENCY_NOTICE


class _StubRAG(RAGService):
    """只记录调用、返回固定卡片的检索替身。"""

    def __init__(self, cards: list[RetrievedCard] | None = None) -> None:
        self._cards = cards or []
        self.calls: list[str] = []

    def retrieve(self, db, question: str, limit: int = 3) -> list[RetrievedCard]:
        self.calls.append(question)
        return list(self._cards)


def _card(**overrides: object) -> RetrievedCard:
    payload: dict[str, object] = {
        "id": 7,
        "title": "宿舍火灾逃生要点",
        "summary": "低姿撤离，不要返回火场取物。",
        "category_id": 1,
        "risk_level": "high",
        "source": None,
        "score": 1.5,
    }
    payload.update(overrides)
    return RetrievedCard(**payload)  # type: ignore[arg-type]


def _service_returning(
    payload: dict | str,
    rag: RAGService | None = None,
) -> tuple[ChatService, dict]:
    """构造一个上游固定返回 [payload] 的服务，并回传捕获到的请求体。"""
    captured: dict = {}
    content = payload if isinstance(payload, str) else json.dumps(payload)

    def handler(request: httpx.Request) -> httpx.Response:
        captured["body"] = json.loads(request.content)
        return httpx.Response(
            200, json={"choices": [{"message": {"content": content}}]}
        )

    client = DeepSeekClient(api_key="sk-test", transport=httpx.MockTransport(handler))
    return ChatService(client, rag=rag), captured


def _ask(service: ChatService, message: str = "宿舍着火怎么办", **kwargs) -> ChatResponse:
    return asyncio.run(service.ask(message, **kwargs))


class TestNormalization:
    def test_full_answer_passes_through(self) -> None:
        service, _ = _service_returning(
            {
                "category": "消防安全",
                "risk_level": "high",
                "answer": "立即撤离，不要返回取物。",
                "steps": ["叫醒室友", "低姿撤离", "拨打 119"],
                "warning": "生命安全优先。",
                "sources": [],
            }
        )

        response = _ask(service)

        assert response.risk_level == "high"
        assert response.category == "消防安全"
        assert response.steps == ["叫醒室友", "低姿撤离", "拨打 119"]
        assert response.warning == "生命安全优先。"

    def test_question_is_echoed_from_request_not_model(self) -> None:
        """question 由服务端填，不采信模型自己写的内容。"""
        service, _ = _service_returning({"answer": "x", "question": "模型编的问题"})
        assert _ask(service, "真实的问题").question == "真实的问题"

    @pytest.mark.parametrize("bad", ["critical", "严重", "", None, 3, ["high"]])
    def test_unknown_risk_level_falls_back_to_medium(self, bad) -> None:
        service, _ = _service_returning({"answer": "x", "risk_level": bad})
        # 宁可让低风险内容显得更谨慎，也不能让高风险内容显得无害
        assert _ask(service).risk_level == "medium"

    def test_risk_level_is_case_insensitive(self) -> None:
        service, _ = _service_returning({"answer": "x", "risk_level": " High "})
        assert _ask(service).risk_level == "high"

    def test_missing_answer_is_an_error_not_a_success(self) -> None:
        service, _ = _service_returning({"risk_level": "high", "steps": ["a"]})
        with pytest.raises(AIServiceError) as exc:
            _ask(service)
        assert exc.value.reason is AIFailure.BAD_RESPONSE

    def test_blank_answer_is_an_error(self) -> None:
        service, _ = _service_returning({"answer": "   "})
        with pytest.raises(AIServiceError):
            _ask(service)

    def test_overlong_category_is_dropped(self) -> None:
        service, _ = _service_returning({"answer": "x", "category": "消防安全与应急管理相关" * 3})
        assert _ask(service).category is None

    def test_non_string_category_is_dropped(self) -> None:
        service, _ = _service_returning({"answer": "x", "category": 123})
        assert _ask(service).category is None

    def test_steps_filter_out_non_strings_and_blanks(self) -> None:
        service, _ = _service_returning(
            {"answer": "x", "steps": ["断电", "", "  ", 42, None, "呼救"]}
        )
        assert _ask(service).steps == ["断电", "呼救"]

    def test_non_list_steps_become_empty(self) -> None:
        service, _ = _service_returning({"answer": "x", "steps": "先断电"})
        assert _ask(service).steps == []


class TestWarningGuarantee:
    """中高风险回答必须带警告。

    这里补的是通用安全提示，而不是编造具体操作 ——
    编造「用湿毛巾捂住口鼻」这类具体做法才是危险的。
    """

    @pytest.mark.parametrize("level", ["medium", "high"])
    def test_missing_warning_is_filled(self, level: str) -> None:
        service, _ = _service_returning({"answer": "x", "risk_level": level})
        assert _ask(service).warning == EMERGENCY_NOTICE

    @pytest.mark.parametrize("level", ["medium", "high"])
    def test_blank_warning_is_filled(self, level: str) -> None:
        service, _ = _service_returning({"answer": "x", "risk_level": level, "warning": "  "})
        assert _ask(service).warning == EMERGENCY_NOTICE

    def test_model_warning_is_kept_when_present(self) -> None:
        service, _ = _service_returning(
            {"answer": "x", "risk_level": "high", "warning": "不要返回火场。"}
        )
        assert _ask(service).warning == "不要返回火场。"

    def test_low_risk_does_not_get_a_warning(self) -> None:
        """低风险也弹警告会让警告失去意义。

        这里刻意用一个不含任何风险关键词的问题：
        只要问题里出现「着火」「触电」这类词，SafetyGuard 就会把等级抬到
        medium 并补上警告（见 test_safety_guard.py）—— 那是它的职责，
        不是本用例要验证的东西。
        """
        service, _ = _service_returning({"answer": "x", "risk_level": "low"})
        assert _ask(service, "安全出口标识是什么颜色").warning is None

    def test_emergency_notice_points_to_emergency_services(self) -> None:
        # 兜底提示必须给出可执行的求助方式，而不是一句空话
        for keyword in ("119", "120", "110"):
            assert keyword in EMERGENCY_NOTICE


class TestHistory:
    def test_history_is_merged_into_the_prompt(self) -> None:
        service, captured = _service_returning({"answer": "x"})

        _ask(service, "那电动车呢？", history=["宿舍着火怎么办", "灭火器怎么用"])

        prompt = captured["body"]["messages"][1]["content"]
        assert "宿舍着火怎么办" in prompt
        assert "灭火器怎么用" in prompt
        assert "那电动车呢？" in prompt

    def test_no_history_keeps_prompt_clean(self) -> None:
        service, captured = _service_returning({"answer": "x"})

        _ask(service, "宿舍着火怎么办")

        prompt = captured["body"]["messages"][1]["content"]
        assert "此前问过" not in prompt


class TestConfigurationGate:
    def test_unconfigured_service_fails_before_request(self) -> None:
        service = ChatService(DeepSeekClient(api_key=""))

        with pytest.raises(AIServiceError) as exc:
            _ask(service)

        assert exc.value.reason is AIFailure.NOT_CONFIGURED
        assert service.is_configured is False


class TestRetrievalWiring:
    """阶段 14：检索结果必须真的走进回答链路。

    `retrieve` 自己测得再透，也证明不了 `ChatService` 调用过它 ——
    这一组守的是这条接线。
    """

    def test_without_a_session_no_retrieval_happens(self) -> None:
        rag = _StubRAG([_card()])
        service, _ = _service_returning({"answer": "x"}, rag=rag)

        response = _ask(service)

        assert rag.calls == []
        assert response.references == []

    def test_retrieved_cards_are_injected_and_echoed_back(self) -> None:
        rag = _StubRAG([_card()])
        service, captured = _service_returning({"answer": "x"}, rag=rag)

        response = _ask(service, db=object())

        prompt = captured["body"]["messages"][1]["content"]
        assert "宿舍火灾逃生要点" in prompt
        assert [item.id for item in response.references] == [7]
        assert response.references[0].category_id == 1

    def test_retrieval_uses_the_question_not_the_history_blob(self) -> None:
        rag = _StubRAG()
        service, _ = _service_returning({"answer": "x"}, rag=rag)

        _ask(service, "那电动车呢？", history=["宿舍着火怎么办"], db=object())

        assert rag.calls == ["那电动车呢？"]

    def test_blocked_answer_still_carries_the_references(self) -> None:
        rag = _StubRAG([_card()])
        service, _ = _service_returning(
            {
                "risk_level": "high",
                "answer": "火势不大时，可以返回火场取回重要证件。",
                "steps": ["返回火场取证件"],
                "sources": ["《消防法》"],
            },
            rag=rag,
        )

        response = _ask(service, db=object())

        assert "返回火场" not in response.answer
        assert response.sources == []
        assert [item.id for item in response.references] == [7]
