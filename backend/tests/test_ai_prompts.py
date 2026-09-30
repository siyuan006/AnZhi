"""阶段 8：提示词中的安全约束。

提示词是安全要求的第一道防线。这些断言看起来很「字符串匹配」，
但它们的作用是：**当有人为了「让回答更活泼」而删掉某条约束时，测试会失败**。
没有这层保护，安全约束会在后续迭代中被悄悄稀释掉。

提示词只是第一道防线，不保证模型一定听话 ——
真正的兜底在阶段 9 的 SafetyGuard。
"""

from __future__ import annotations

from app.services.ai.prompts import ANSWER_SCHEMA_HINT, SYSTEM_PROMPT, build_user_prompt


class TestSafetyConstraints:
    def test_prioritizes_life_safety(self) -> None:
        assert "生命安全优先" in SYSTEM_PROMPT

    def test_lists_emergency_numbers(self) -> None:
        for number in ("119", "120", "110"):
            assert number in SYSTEM_PROMPT, f"提示词缺少紧急电话 {number}"

    def test_forbids_dangerous_operations(self) -> None:
        # 这几条是真实事故里最常见的致命错误做法
        assert "返回火场" in SYSTEM_PROMPT
        assert "徒手" in SYSTEM_PROMPT
        assert "什么不要做" in SYSTEM_PROMPT

    def test_forbids_fabricating_sources(self) -> None:
        assert "绝对不要编造出处" in SYSTEM_PROMPT

    def test_high_risk_requires_brevity(self) -> None:
        assert "不做长篇科普" in SYSTEM_PROMPT

    def test_admits_uncertainty_instead_of_guessing(self) -> None:
        assert "不要编造" in SYSTEM_PROMPT or "不要给出一个听起来确定" in SYSTEM_PROMPT

    def test_discourages_dramatizing_emergencies(self) -> None:
        assert "不娱乐化处理紧急情况" in SYSTEM_PROMPT


class TestOutputContract:
    def test_requires_json_only_output(self) -> None:
        assert "只输出一个 JSON 对象" in SYSTEM_PROMPT

    def test_schema_lists_every_response_field(self) -> None:
        for field in ("category", "risk_level", "answer", "steps", "sources", "warning"):
            assert field in ANSWER_SCHEMA_HINT, f"输出结构缺少 {field}"

    def test_schema_keeps_risk_level_values_in_sync_with_the_api(self) -> None:
        # 与 app/schemas/chat.py 的 VALID_RISK_LEVELS 必须一致，
        # 否则模型会输出一个客户端认不出的等级
        for level in ("low", "medium", "high"):
            assert level in ANSWER_SCHEMA_HINT

    def test_schema_contains_all_six_categories(self) -> None:
        for name in (
            "消防安全",
            "用电安全",
            "交通安全",
            "校园安全",
            "网络与反诈安全",
            "自然灾害与应急",
        ):
            assert name in ANSWER_SCHEMA_HINT, f"输出结构缺少分类「{name}」"


class TestBuildUserPrompt:
    def test_plain_question(self) -> None:
        prompt = build_user_prompt("宿舍着火怎么办")
        assert "宿舍着火怎么办" in prompt
        assert "指定分类" not in prompt

    def test_with_category(self) -> None:
        prompt = build_user_prompt("插座冒烟", category="用电安全")
        assert "用电安全" in prompt
        assert "插座冒烟" in prompt
