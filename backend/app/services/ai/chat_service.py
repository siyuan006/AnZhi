"""AI 问答编排。

流程（PROJECT_SPEC 第三十六、三十七节）：

    用户问题 → ChatService → DeepSeek → 规范化 → SafetyGuard → 结构化回答

本文件负责三件事：
    1. 校验并规范化模型返回的内容（模型不保证听话）
    2. 把规范化后的回答交给 [SafetyGuard] 做安全审查
    3. 把上游的失败翻译成对用户有意义的说明

**边界划分：** 规范化解决的是「模型返回的东西能不能用」——
字段缺失、类型不对、风险等级不认识。
安全审查解决的是「这条回答能不能给用户看」——
危险操作、缺警告、风险等级判低了。
后者全部在 [safety_guard] 里，本模块只负责在正确的时机调用它。
"""

from __future__ import annotations

import logging

from app.schemas.chat import ChatResponse
from app.services.ai.deepseek_client import DeepSeekClient
from app.services.ai.errors import AIFailure, AIServiceError
from app.services.ai.safety_guard import SafetyGuard

logger = logging.getLogger("anzhi")

VALID_RISK_LEVELS = ("low", "medium", "high")

# 风险等级无法识别时的兜底值。
# 选 medium 而不是 low：真正的低风险内容被标成中风险，代价只是用户多看一句提示；
# 而真正的高风险内容被标成低风险，代价是用户按低风险的语气去处理危险情况。
# 两种误判的代价不对称，因此往谨慎的一侧靠。
FALLBACK_RISK_LEVEL = "medium"

# 分类字段的长度上限。模型偶尔会返回一整句话，这里只做形状校验，
# **不校验分类名是否在六大分类内** —— 那需要在后端再存一份分类表，
# 而分类名已经在数据库种子、接口、前端常量三处存在，
# 再复制第四份正是 AI_RULES 第十二节警告过的做法。
MAX_CATEGORY_LENGTH = 20


class ChatService:
    """问答业务逻辑。"""

    def __init__(
        self,
        client: DeepSeekClient | None = None,
        guard: SafetyGuard | None = None,
    ) -> None:
        self._client = client or DeepSeekClient()
        self._guard = guard or SafetyGuard()

    @property
    def is_configured(self) -> bool:
        return self._client.is_configured

    async def ask(
        self,
        message: str,
        category: str | None = None,
        history: list[str] | None = None,
    ) -> ChatResponse:
        """回答一个安全问题。

        失败时抛 [AIServiceError]，由路由层翻译成 HTTP 状态码。
        """
        # 多轮上下文只拼接用户侧的提问。
        # 不接受客户端传来的「助手回复」：那等于把模型的历史发言交给客户端伪造，
        # 对一个安全产品来说，这可以变成「先让模型认为某危险做法没问题」的注入手段。
        prompt = message
        if history:
            earlier = "\n".join(f"- {item}" for item in history)
            prompt = f"【该用户此前问过】\n{earlier}\n\n【当前问题】\n{message}"

        raw = await self._client.complete_json(prompt, category)
        return self._to_response(raw, question=message)

    # ------------------------------------------------------------------
    # 规范化
    # ------------------------------------------------------------------

    def _to_response(self, raw: dict, *, question: str) -> ChatResponse:
        """把模型返回的任意 JSON 规范化成 [ChatResponse]。"""
        answer = raw.get("answer")
        if not isinstance(answer, str) or not answer.strip():
            # 没有正文的回答没有任何价值，不能包装成「成功」返回
            logger.error("模型返回缺少 answer 字段：%s", list(raw.keys()))
            raise AIServiceError(
                AIFailure.BAD_RESPONSE,
                "AI 没有给出有效回答，请重新提问",
            )

        # 先规范化，再审查。顺序不能颠倒：
        # 审查层假定拿到的是干净数据（字段类型正确、风险等级可识别），
        # 让它同时承担类型兜底，规则会变得难以读、难以测。
        guarded = self._guard.review(
            question=question,
            answer=answer.strip(),
            steps=self._string_list(raw.get("steps")),
            sources=self._string_list(raw.get("sources")),
            warning=self._text(raw.get("warning")),
            risk_level=self._normalize_risk(raw.get("risk_level")),
        )

        return ChatResponse(
            question=question,
            category=self._normalize_category(raw.get("category")),
            risk_level=guarded.risk_level,
            answer=guarded.answer,
            steps=guarded.steps,
            sources=guarded.sources,
            warning=guarded.warning,
        )

    @staticmethod
    def _normalize_risk(value: object) -> str:
        if isinstance(value, str) and value.strip().lower() in VALID_RISK_LEVELS:
            return value.strip().lower()
        logger.warning("模型返回了无法识别的风险等级 %r，按 %s 处理", value, FALLBACK_RISK_LEVEL)
        return FALLBACK_RISK_LEVEL

    @staticmethod
    def _normalize_category(value: object) -> str | None:
        text = ChatService._text(value)
        if text is None or len(text) > MAX_CATEGORY_LENGTH:
            return None
        return text

    @staticmethod
    def _text(value: object) -> str | None:
        """把可选字段转成去空白的字符串，无效值一律返回 None。"""
        if not isinstance(value, str):
            return None
        text = value.strip()
        return text or None

    @staticmethod
    def _string_list(value: object) -> list[str]:
        """解析字符串数组，过滤掉空条目与非字符串元素。"""
        if not isinstance(value, list):
            return []
        return [item.strip() for item in value if isinstance(item, str) and item.strip()]
