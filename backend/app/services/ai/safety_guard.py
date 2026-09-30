"""回答安全审查（PROJECT_SPEC 第三十七节）。

链路：

    用户问题 → 风险判断 → DeepSeek → SafetyGuard → 最终回答

模型不保证听话，提示词只能**降低**出问题的概率，不能消除它。
本模块是模型输出与用户之间的最后一道人工规则。

--------------------------------------------------------------------------
三条设计约束
--------------------------------------------------------------------------

**一、只允许往安全的方向改变回答。**

    ✅ 抬高风险等级（模型判 low，但问题里是正在发生的危险 → 抬到 high）
    ✅ 补上警告、补上紧急联系方式
    ✅ 整条拦下含危险操作的回答，换成保守的兜底话术
    ❌ 降低风险等级
    ❌ 删掉已有的警告
    ❌ 编造操作步骤

最后一条尤其重要：一个「看起来专业但其实是编的」操作建议，
比直接说「这一点请咨询专业人员」危险得多。所以本模块
**只会删减和补充警示，绝不会新增任何操作步骤**。

**二、不调用第二次大模型。**

让审查层自己也依赖模型，等于把「模型可能出错」这件事叠了两次，
而且「回答为什么被拦下」会变得不可复现、不可测试。
安全审查必须是确定性的：同样的输入永远得到同样的结论。

**三、区分「叫用户别做」和「叫用户去做」。**

提示词明确要求模型说明「什么不要做」，所以
「切勿返回火场取物」这种**正确**的回答里，
必然包含「返回火场」这四个字。
用子串匹配直接拦下，会把最该保留的回答全部误杀。
因此危险短语必须先做**否定判定**：同一个小句内如果出现了
「不要 / 切勿 / 严禁」之类的否定词，那是在警告，不是在教唆。
"""

from __future__ import annotations

import logging
import re
from dataclasses import dataclass, field

logger = logging.getLogger("anzhi")

VALID_RISK_LEVELS = ("low", "medium", "high")

_RISK_ORDER = {"low": 0, "medium": 1, "high": 2}

# 中高风险回答缺少 warning 时补上的通用提示。
# 这是一句恒为真的安全常识，不是编造的具体操作 ——
# 编造「请用湿毛巾捂住口鼻」这种具体做法才是危险的。
EMERGENCY_NOTICE = (
    "以上内容仅供参考。若情况紧急或已有人受伤，"
    "请立即拨打 119（火警）/ 120（急救）/ 110（报警），并听从专业人员指挥。"
)

# 拦截危险回答后，替换上去的正文。
# 刻意不提供任何操作步骤：我们此刻已经知道模型给的步骤里
# 至少有一条是危险的，但无法确定其余几条是否也受影响。
# 半截被删过的急救建议可能比没有建议更危险。
#
# 这里重复一次求助电话，是为了让「只读正文、不看警告框」的用户
# 也能立刻知道该做什么。安全提示上的重复是有意的，不是冗余。
BLOCKED_NOTICE = (
    "这条回答包含可能造成伤害的做法，已被安全审查拦下，不能作为处置依据。"
    "请立即拨打 119（火警）/ 120（急救）/ 110（报警），并听从专业人员指挥。"
)

# ---------------------------------------------------------------------------
# 危险操作短语
#
# 只放「照着做会直接危及生命」的：
#   · 重进危险区域（火场、坍塌建筑）
#   · 用电梯逃生
#   · 跳窗 / 跳楼
#   · 徒手接触带电体、带电灭火
#   · 用明火检漏
#   · 无防护施救
#
# 不放「可能不妥但属于程度问题」的（例如「用湿毛巾捂住口鼻」这类
# 有争议但并非直接致命的做法）—— 规则集越宽，误杀越多，
# 误杀多了这个模块就会被当成噪音关掉，反而更不安全。
# ---------------------------------------------------------------------------

DANGEROUS_INSTRUCTIONS: tuple[str, ...] = (
    # 重新进入危险区域
    "返回火场",
    "回到火场",
    "冲回火场",
    "返回室内取",
    "回房间拿",
    "回去取",
    "返回取",
    "进入火场",
    "跑回去拿",
    # 火灾时乘电梯
    "乘坐电梯逃生",
    "乘电梯逃生",
    "坐电梯逃生",
    "使用电梯逃生",
    "搭电梯逃生",
    # 跳窗跳楼
    "跳窗",
    "跳楼",
    "从窗户跳下",
    "从楼上跳",
    # 触电处置
    "徒手拉",
    "用手直接拉",
    "徒手去拉",
    "直接用手拉开",
    "用手去拉触电",
    # 带电灭火
    "用水扑救带电",
    "用水浇带电",
    "直接用水扑灭带电",
    # 燃气检漏
    "用打火机检查",
    "用火柴检查",
    "用明火检查",
    "打开阀门检查",
    # 无防护施救
    "冲进火场救人",
    "独自进入火场",
)

# 否定词：出现在危险短语**所在小句**内，说明这句话是在劝阻而不是在教唆
_NEGATIONS: tuple[str, ...] = (
    "不要",
    "不能",
    "不可",
    "不得",
    "不应",
    "不准",
    "别",
    "切勿",
    "切忌",
    "严禁",
    "禁止",
    "绝不",
    "避免",
    "千万不要",
    "勿",
    "严禁",
)

# 小句边界：在这些标点处断开，否定词只在同一个小句内生效。
# 这样「不要犹豫，立即返回火场取物」仍会被判为危险指令，
# 因为「立即返回火场取物」这个小句里没有否定词。
_CLAUSE_SPLIT = re.compile(r"[，。；！？!?;,\n\r\t]+")

# ---------------------------------------------------------------------------
# 风险关键词
#
# 这组词只用来**抬高**风险等级，从不降低。
# 误抬高的代价是多一句警告；漏抬高的代价是用户按低风险的语气
# 去处理一件正在危及生命的事。两者不对称，所以宁可多抬。
# ---------------------------------------------------------------------------

# 正在发生 / 即将发生的危险 → 至少 high
IMMINENT_HAZARDS: tuple[str, ...] = (
    "着火了",
    "起火了",
    "已经着火",
    "正在着火",
    "现在着火",
    "烧起来",
    "冒烟了",
    "有浓烟",
    "有人受伤",
    "有人受伤了",
    "有人昏迷",
    "昏迷",
    "流血不止",
    "大出血",
    "触电了",
    "被电了",
    "有人触电",
    "溺水了",
    "有人溺水",
    "喘不上气",
    "无法呼吸",
    "呼吸困难",
    "心脏骤停",
    "没有呼吸",
    "被困",
    "出不去了",
    "出不去",
    "门打不开",
    "闻到燃气",
    "燃气味",
    "煤气味",
    "燃气泄漏",
    "煤气泄漏",
    "地震了",
    "正在地震",
    "晃得厉害",
    "有人倒地",
    "塌了",
    "中毒了",
)

# 明确的风险主题 → 至少 medium
HAZARD_TOPICS: tuple[str, ...] = (
    "火灾",
    "火场",
    "起火",
    "着火",
    "灭火",
    "消防",
    "触电",
    "漏电",
    "短路",
    "高压电",
    "变压器",
    "燃气",
    "煤气",
    "一氧化碳",
    "中毒",
    "溺水",
    "地震",
    "台风",
    "洪水",
    "泥石流",
    "雷电",
    "高空",
    "坠落",
    "摔伤",
    "烫伤",
    "烧伤",
    "车祸",
    "交通事故",
    "急救",
    "心肺复苏",
    "止血",
    "电梯故障",
    "被困电梯",
    "诈骗",
    "转账",
    "验证码",
    "校园欺凌",
    "猥亵",
    "性骚扰",
)

# 紧急联系方式。高风险 / 紧急场景的警告里必须至少出现其中一类，
# 否则用户在最需要求助的时候看不到号码。
_EMERGENCY_NUMBERS: tuple[str, ...] = ("119", "120", "110")

# 过度确定的措辞（AI_RULES 第十节「信息不足时不得过度确定」）。
# 命中不拦截 —— 这类措辞最多是不够谨慎，不至于致命 ——
# 但会保证回答带上警告，并把情况记进日志。
OVERCERTAIN_PHRASES: tuple[str, ...] = (
    "绝对安全",
    "一定不会",
    "肯定不会",
    "保证不会",
    "百分之百",
    "百分百",
    "万无一失",
    "绝对不会",
    "完全可以放心",
    "没有任何危险",
)


@dataclass(frozen=True)
class GuardedAnswer:
    """审查后的回答，以及审查过程中做了什么。"""

    answer: str
    steps: list[str]
    sources: list[str]

    #: 安全警告。低风险且模型没主动提醒时为 None ——
    #: 用 None 而不是空串表示「这里没有警告」，客户端可以直接判空。
    warning: str | None
    risk_level: str

    #: 整条回答是否被拦下并替换成了兜底话术
    blocked: bool = False

    #: 风险等级是否被审查层抬高过
    risk_raised: bool = False

    #: 人工可读的处置记录，供日志与测试使用
    reasons: tuple[str, ...] = field(default_factory=tuple)


class SafetyGuard:
    """对模型输出做确定性审查。

    无状态、无 I/O，可以放心地在任何地方构造和调用。
    """

    def review(
        self,
        *,
        question: str,
        answer: str,
        steps: list[str],
        sources: list[str],
        warning: str | None,
        risk_level: str,
    ) -> GuardedAnswer:
        """审查并（必要时）修正一条回答。

        参数都是上一步规范化过的值，本方法不再做类型兜底。
        """
        reasons: list[str] = []

        # ---- 1. 风险等级：只抬不降 -------------------------------------
        risk_level, risk_raised, risk_reason = self._raise_risk(question, risk_level)
        if risk_reason:
            reasons.append(risk_reason)

        # ---- 2. 危险操作：命中即整条拦下 -------------------------------
        hits = self.find_dangerous_instructions([answer, *steps])
        if hits:
            reasons.append(f"命中危险操作：{'、'.join(hits)}")
            logger.warning(
                "SafetyGuard 拦下一条回答（问题：%s），命中危险操作 %s",
                question[:80],
                hits,
            )
            return GuardedAnswer(
                # 正文说明「为什么被拦下」，警告框给出求助方式 ——
                # 两者不能填成同一段话，否则客户端会把同一段文字
                # 在正文区和警告区各渲染一遍。
                answer=BLOCKED_NOTICE,
                steps=[],
                # 原回答的来源不再可信，一并清空
                sources=[],
                warning=EMERGENCY_NOTICE,
                risk_level="high",
                blocked=True,
                risk_raised=risk_raised,
                reasons=tuple(reasons),
            )

        # ---- 3. 过度确定：不拦截，但必须有警告 -------------------------
        if self._is_overcertain(answer):
            reasons.append("回答含过度确定的措辞")
            warning = warning or EMERGENCY_NOTICE

        # ---- 4. 警告：中高风险必须有，紧急场景必须带号码 ---------------
        warning = self._ensure_warning(
            warning=warning,
            risk_level=risk_level,
            emergency=self._is_emergency(question),
            reasons=reasons,
        )

        # ---- 5. 高风险缺少可执行步骤：只记录，不编造 -------------------
        if risk_level == "high" and not steps:
            reasons.append("高风险回答没有给出可执行步骤")
            logger.warning("高风险回答缺少 steps（问题：%s）", question[:80])

        if reasons:
            logger.info("SafetyGuard 处置：%s", "；".join(reasons))

        return GuardedAnswer(
            answer=answer,
            steps=list(steps),
            sources=list(sources),
            warning=warning,
            risk_level=risk_level,
            blocked=False,
            risk_raised=risk_raised,
            reasons=tuple(reasons),
        )

    # ------------------------------------------------------------------
    # 危险操作检测
    # ------------------------------------------------------------------

    @classmethod
    def find_dangerous_instructions(cls, texts: list[str]) -> list[str]:
        """找出**未被否定**的危险操作短语。

        返回命中的短语（去重、保持出现顺序）。
        """
        hits: list[str] = []
        for text in texts:
            if not text:
                continue
            for clause in _CLAUSE_SPLIT.split(text):
                if any(negation in clause for negation in _NEGATIONS):
                    continue
                for phrase in DANGEROUS_INSTRUCTIONS:
                    if phrase in clause and phrase not in hits:
                        hits.append(phrase)
        return hits

    # ------------------------------------------------------------------
    # 风险等级
    # ------------------------------------------------------------------

    @classmethod
    def _raise_risk(cls, question: str, risk_level: str) -> tuple[str, bool, str]:
        """按问题内容抬高风险等级，绝不降低。"""
        floor = "low"
        matched: list[str] = []

        for keyword in IMMINENT_HAZARDS:
            if keyword in question:
                floor = "high"
                matched.append(keyword)
                break

        if floor != "high":
            for keyword in HAZARD_TOPICS:
                if keyword in question:
                    floor = "medium"
                    matched.append(keyword)
                    break

        if _RISK_ORDER[floor] <= _RISK_ORDER.get(risk_level, 1):
            return risk_level, False, ""

        return (
            floor,
            True,
            f"模型判为 {risk_level}，问题含「{matched[0]}」，抬到 {floor}",
        )

    @classmethod
    def _is_emergency(cls, question: str) -> bool:
        return any(keyword in question for keyword in IMMINENT_HAZARDS)

    # ------------------------------------------------------------------
    # 警告
    # ------------------------------------------------------------------

    @classmethod
    def _ensure_warning(
        cls,
        *,
        warning: str | None,
        risk_level: str,
        emergency: bool,
        reasons: list[str],
    ) -> str | None:
        """保证该有警告的地方有警告，该有号码的地方有号码。

        返回 None 表示「这条回答不需要警告」。
        """
        text = (warning or "").strip()

        # 低风险且模型自己写了警告 —— 保留原话，不做画蛇添足
        if risk_level == "low" and not emergency:
            return text or None

        if not text:
            reasons.append(f"{risk_level} 风险但模型未给警告，已补通用提示")
            return EMERGENCY_NOTICE

        if emergency and not any(number in text for number in _EMERGENCY_NUMBERS):
            reasons.append("紧急场景的警告缺少求助电话，已补上")
            return f"{text}\n{EMERGENCY_NOTICE}"

        return text

    # ------------------------------------------------------------------
    # 过度确定
    # ------------------------------------------------------------------

    @staticmethod
    def _is_overcertain(answer: str) -> bool:
        return any(phrase in answer for phrase in OVERCERTAIN_PHRASES)
