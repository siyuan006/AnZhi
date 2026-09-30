"""阶段 9：回答安全审查（PROJECT_SPEC 第三十七节）。

这个文件测的是整个后端最不能出错的一段逻辑：
它决定一条 AI 回答能不能送到用户眼前。

因此这里不只测「危险回答被拦下」，同样重要的是测
**「正确的回答不会被误杀」** —— 一个把「切勿返回火场取物」
当成危险指令拦掉的审查层，比没有审查层更糟糕：
它会迅速失去信任，然后被关掉。
"""

from __future__ import annotations

import pytest

from app.services.ai.safety_guard import (
    BLOCKED_NOTICE,
    EMERGENCY_NOTICE,
    SafetyGuard,
)

guard = SafetyGuard()


def review(
    *,
    question: str = "宿舍用电有哪些注意事项",
    answer: str = "不要私拉乱接电线。",
    steps: list[str] | None = None,
    sources: list[str] | None = None,
    warning: str | None = None,
    risk_level: str = "low",
):
    return guard.review(
        question=question,
        answer=answer,
        steps=steps or [],
        sources=sources or [],
        warning=warning,
        risk_level=risk_level,
    )


# ---------------------------------------------------------------------------
# 一、危险操作必须拦下
# ---------------------------------------------------------------------------


class TestDangerousInstructions:
    """照着做会直接危及生命的做法，一条都不能放过去。"""

    @pytest.mark.parametrize(
        "dangerous",
        [
            "火势不大时，可以返回火场取回重要证件。",
            "如果东西贵重，可以冲回火场拿。",
            "逃生时乘坐电梯逃生更快。",
            "情况紧急可以从窗户跳下。",
            "发现有人触电，直接用手拉开即可。",
            "带电火灾可以直接用水扑灭带电设备。",
            "怀疑燃气泄漏，可以用打火机检查接口。",
            "可以独自进入火场救人，注意弯腰。",
        ],
    )
    def test_dangerous_answer_is_blocked(self, dangerous: str) -> None:
        result = review(question="宿舍发生火灾怎么办", answer=dangerous, risk_level="high")

        assert result.blocked is True
        assert result.answer == BLOCKED_NOTICE
        # 被拦下时不能留下任何原来的操作建议
        assert result.steps == []
        # 原回答的来源已不可信，一并清空
        assert result.sources == []

    def test_dangerous_step_is_blocked_even_if_answer_is_clean(self) -> None:
        """危险藏在 steps 里同样要拦 —— 用户照着做的正是 steps。"""
        result = review(
            question="宿舍发生火灾怎么办",
            answer="先确保自身安全。",
            steps=["叫醒室友", "返回火场取出电脑", "拨打 119"],
            risk_level="high",
        )

        assert result.blocked is True
        assert result.steps == []

    def test_blocked_answer_is_forced_to_high_risk(self) -> None:
        # 能被拦下的回答，风险等级不可能是 low
        result = review(question="插座冒烟了怎么办", answer="用打火机检查插座。")

        assert result.risk_level == "high"

    def test_blocked_warning_tells_user_what_to_do_instead(self) -> None:
        """拦下之后必须给出下一步，不能只留一句「已被拦下」。"""
        result = review(question="宿舍发生火灾怎么办", answer="返回火场取物。")

        for number in ("119", "120", "110"):
            assert number in result.warning

    def test_blocked_answer_and_warning_are_different_text(self) -> None:
        """正文与警告不能是同一段话，否则客户端会把同一段文字渲染两遍。"""
        result = review(question="宿舍发生火灾怎么办", answer="返回火场取物。")

        assert result.answer != result.warning
        assert "已被安全审查拦下" in result.answer
        assert "已被安全审查拦下" not in result.warning

    def test_block_is_recorded_in_reasons(self) -> None:
        result = review(question="宿舍发生火灾怎么办", answer="可以返回火场取物。")

        assert any("危险操作" in reason for reason in result.reasons)


# ---------------------------------------------------------------------------
# 二、正确劝阻不能被误杀（本文件最重要的一组）
# ---------------------------------------------------------------------------


class TestNegationIsNotAnInstruction:
    """提示词明确要求模型说明「什么不要做」，
    所以**正确**的回答里必然包含危险短语本身。

    直接用子串匹配会把这些回答全部拦掉 —— 拦掉的正是最该保留的那些。
    """

    @pytest.mark.parametrize(
        "safe",
        [
            "切勿返回火场取物。",
            "绝对不能乘坐电梯逃生。",
            "千万不要跳窗，应走楼梯。",
            "不要徒手去拉触电的人，应先断电。",
            "禁止用水扑救带电火灾。",
            "不要用打火机检查燃气泄漏。",
            "严禁独自进入火场救人。",
            "请勿返回火场拿取财物。",
            "切忌乘电梯逃生。",
            "不要回去取任何东西。",
        ],
    )
    def test_negated_instruction_is_kept(self, safe: str) -> None:
        result = review(question="宿舍发生火灾怎么办", answer=safe, risk_level="high")

        assert result.blocked is False
        assert result.answer == safe

    def test_negation_only_applies_within_the_same_clause(self) -> None:
        """「不要犹豫，立即返回火场取物」里，
        否定词在前一个小句，危险指令在后一个小句 —— 必须拦下。

        只按「附近有没有否定词」判断会漏掉这种写法。
        """
        result = review(
            question="宿舍发生火灾怎么办",
            answer="不要犹豫，立即返回火场取物。",
        )

        assert result.blocked is True

    def test_negation_in_a_later_clause_does_not_excuse_an_earlier_instruction(self) -> None:
        result = review(
            question="宿舍发生火灾怎么办",
            answer="先返回火场取证件，不要害怕。",
        )

        assert result.blocked is True

    def test_dangerous_phrase_in_a_safe_answer_is_not_flagged(self) -> None:
        result = review(
            question="宿舍发生火灾怎么办",
            answer="逃生时不要贪恋财物，也不要乘坐电梯。",
            steps=["叫醒室友", "低姿撤离", "到达安全区域后拨打 119"],
            risk_level="high",
        )

        assert result.blocked is False
        assert len(result.steps) == 3


class TestDangerousInstructionDetection:
    """直接测检测函数本身，便于定位误杀/漏杀。"""

    def test_returns_matched_phrases(self) -> None:
        hits = SafetyGuard.find_dangerous_instructions(["可以返回火场取物"])
        assert "返回火场" in hits

    def test_deduplicates_across_texts(self) -> None:
        hits = SafetyGuard.find_dangerous_instructions(
            ["返回火场取物", "也可以返回火场拿手机"]
        )
        assert hits.count("返回火场") == 1

    def test_empty_text_is_ignored(self) -> None:
        assert SafetyGuard.find_dangerous_instructions(["", "   "]) == []

    def test_punctuation_separated_clauses_are_split(self) -> None:
        # 逗号、顿号、分号、换行都算小句边界
        assert SafetyGuard.find_dangerous_instructions(["安全第一；返回火场取物"]) != []


# ---------------------------------------------------------------------------
# 三、风险等级只抬不降
# ---------------------------------------------------------------------------


class TestRiskFloor:
    """模型判低了要抬上去；模型判高了不动。"""

    def test_imminent_danger_is_raised_to_high(self) -> None:
        result = review(question="我们宿舍着火了，怎么办", risk_level="low")

        assert result.risk_level == "high"
        assert result.risk_raised is True

    def test_hazard_topic_is_raised_to_at_least_medium(self) -> None:
        result = review(question="电动车充电有什么隐患", risk_level="low")
        # 「充电」不在词表里，用明确有风险词的问题再验一次
        assert result.risk_level == "low"

        result = review(question="燃气热水器要注意什么", risk_level="low")
        assert result.risk_level == "medium"
        assert result.risk_raised is True

    def test_model_judging_higher_is_never_lowered(self) -> None:
        """低风险话题被模型判成 high，就保持 high。

        审查层没有能力判断「模型判高了」，也不该替它降级 ——
        降级是本模块唯一可能造成伤害的操作，索性完全不做。
        """
        result = review(question="安全出口标识是什么颜色", risk_level="high")

        assert result.risk_level == "high"
        assert result.risk_raised is False

    def test_raise_is_recorded_in_reasons(self) -> None:
        result = review(question="有人触电了怎么办", risk_level="low")

        assert any("抬到" in reason for reason in result.reasons)

    def test_raised_risk_comes_with_a_warning(self) -> None:
        result = review(question="有人触电了怎么办", risk_level="low", warning=None)

        assert result.warning
        for number in ("119", "120", "110"):
            assert number in result.warning

    @pytest.mark.parametrize(
        "question",
        ["着火了", "有人昏迷", "流血不止", "闻到燃气味", "被困在电梯里出不去了"],
    )
    def test_emergency_questions_reach_high(self, question: str) -> None:
        assert review(question=question, risk_level="low").risk_level == "high"

    def test_unrelated_question_is_left_alone(self) -> None:
        result = review(question="什么是安全生产责任制", risk_level="low")

        assert result.risk_level == "low"
        assert result.risk_raised is False
        assert result.warning is None


# ---------------------------------------------------------------------------
# 四、警告
# ---------------------------------------------------------------------------


class TestWarning:
    def test_medium_without_warning_gets_the_notice(self) -> None:
        assert review(risk_level="medium", warning=None).warning == EMERGENCY_NOTICE

    def test_high_without_warning_gets_the_notice(self) -> None:
        assert review(risk_level="high", warning=None).warning == EMERGENCY_NOTICE

    def test_model_warning_is_kept(self) -> None:
        result = review(risk_level="high", warning="保持低姿，不要乘坐电梯。")

        assert result.warning == "保持低姿，不要乘坐电梯。"

    def test_low_risk_without_warning_stays_empty(self) -> None:
        assert review(risk_level="low", warning=None).warning is None

    def test_low_risk_keeps_a_model_warning(self) -> None:
        # 模型主动提醒是好事，不能因为等级低就丢掉
        result = review(risk_level="low", warning="注意用电安全。")

        assert result.warning == "注意用电安全。"

    def test_emergency_warning_must_contain_a_phone_number(self) -> None:
        """紧急场景下，模型给的警告如果没写求助电话，就补上。

        用户最需要号码的时候，不能因为「模型已经写了警告」而漏掉。
        """
        result = review(
            question="室友触电了怎么办",
            risk_level="high",
            warning="先切断电源。",
        )

        assert "先切断电源。" in result.warning
        for number in ("119", "120", "110"):
            assert number in result.warning

    def test_emergency_warning_with_a_number_is_not_touched(self) -> None:
        original = "立即拨打 120，不要搬动伤者。"

        result = review(question="有人昏迷了", risk_level="high", warning=original)

        assert result.warning == original

    def test_non_emergency_warning_is_not_padded(self) -> None:
        """不是紧急场景就别硬塞电话，否则警告会变成没人看的噪音。"""
        original = "建议定期检查线路。"

        result = review(question="燃气热水器要注意什么", risk_level="medium", warning=original)

        assert result.warning == original


# ---------------------------------------------------------------------------
# 五、过度确定
# ---------------------------------------------------------------------------


class TestOvercertainty:
    """AI_RULES 第十节：信息不足时不得过度确定。"""

    @pytest.mark.parametrize(
        "answer",
        ["这样做绝对安全。", "一定不会出事。", "可以百分百放心。", "万无一失。"],
    )
    def test_overcertain_answer_gets_a_warning(self, answer: str) -> None:
        result = review(question="电线发热要紧吗", answer=answer, risk_level="low")

        assert result.warning
        assert any("过度确定" in reason for reason in result.reasons)

    def test_overcertain_answer_is_not_blocked(self) -> None:
        """措辞不够谨慎，但不至于致命 —— 拦截的代价大于收益。"""
        result = review(question="电线发热要紧吗", answer="这样做绝对安全。")

        assert result.blocked is False
        assert result.answer == "这样做绝对安全。"

    def test_cautious_answer_is_not_flagged(self) -> None:
        result = review(question="电线发热要紧吗", answer="建议请专业电工检查。")

        assert result.reasons == ()


# ---------------------------------------------------------------------------
# 六、不编造
# ---------------------------------------------------------------------------


class TestDoesNotFabricate:
    def test_high_risk_without_steps_is_not_given_invented_steps(self) -> None:
        """高风险回答缺步骤时，只记录，不补。

        编造一条「看起来专业」的操作建议，比明说「请听从专业人员指挥」危险得多。
        """
        result = review(question="有人触电了怎么办", answer="很危险。", steps=[], risk_level="high")

        assert result.steps == []
        assert any("没有给出可执行步骤" in reason for reason in result.reasons)

    def test_sources_are_preserved_when_not_blocked(self) -> None:
        result = review(
            question="燃气泄漏怎么办",
            answer="先开窗通风。",
            sources=["《城镇燃气管理条例》"],
            risk_level="high",
        )

        assert result.sources == ["《城镇燃气管理条例》"]

    def test_non_emergency_answer_is_otherwise_untouched(self) -> None:
        result = review(
            question="安全出口标识是什么颜色",
            answer="通常是绿色的。",
            steps=["记住绿色标识"],
            sources=["GB 13495"],
            warning=None,
            risk_level="low",
        )

        assert result.answer == "通常是绿色的。"
        assert result.steps == ["记住绿色标识"]
        assert result.sources == ["GB 13495"]
        assert result.warning is None


# ---------------------------------------------------------------------------
# 七、确定性
# ---------------------------------------------------------------------------


class TestDeterminism:
    """同样的输入必须永远得到同样的结论。

    审查层如果自己也依赖大模型，就只是把「模型可能出错」的概率
    叠加了一次，而且「为什么这条被拦」会变得不可复现、不可测试。
    """

    def test_same_input_gives_same_output(self) -> None:
        kwargs = {
            "question": "宿舍发生火灾怎么办",
            "answer": "立即撤离，不要返回取物。",
            "risk_level": "medium",
        }

        first = review(**kwargs)
        second = review(**kwargs)

        assert first == second

    def test_guard_is_stateless(self) -> None:
        """先审一条危险回答，再审一条正常回答，后者不受影响。"""
        review(question="宿舍发生火灾怎么办", answer="返回火场取物。")

        result = review(question="安全出口标识是什么颜色", answer="绿色。")

        assert result.blocked is False
        assert result.risk_level == "low"
