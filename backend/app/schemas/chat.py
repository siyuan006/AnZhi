"""AI 问答相关数据结构。对应 docs/API.md 第 3 节与 PROJECT_SPEC 第九节。"""

from __future__ import annotations

from pydantic import BaseModel, Field, field_validator

# 多轮上下文的约束
MAX_HISTORY_ITEMS = 6
MAX_HISTORY_ITEM_LENGTH = 500


class ChatRequest(BaseModel):
    """`POST /api/chat` 请求体。"""

    message: str = Field(
        ...,
        min_length=1,
        max_length=1000,
        description="用户问题",
        examples=["宿舍发生火灾怎么办？"],
    )
    category: str | None = Field(
        None,
        max_length=50,
        description="指定分类；不传则由模型自行判断",
    )
    history: list[str] = Field(
        default_factory=list,
        max_length=MAX_HISTORY_ITEMS,
        description=(
            "此前的用户提问，用于多轮上下文。"
            "**只接受用户侧的提问文本**，不接受客户端伪造的助手回复"
        ),
    )

    @field_validator("message")
    @classmethod
    def _message_not_blank(cls, value: str) -> str:
        """拦截「全是空格」的输入。

        `min_length=1` 只能挡住空串，但 "   " 同样不是一个问题，
        放行只会白白消耗一次 API 调用。
        """
        stripped = value.strip()
        if not stripped:
            raise ValueError("问题不能为空")
        return stripped

    @field_validator("history")
    @classmethod
    def _clean_history(cls, value: list[str]) -> list[str]:
        """去掉空条目，并只保留最近若干条。"""
        cleaned = [item.strip()[:MAX_HISTORY_ITEM_LENGTH] for item in value if item.strip()]
        return cleaned[-MAX_HISTORY_ITEMS:]


class ChatReference(BaseModel):
    """回答参考到的知识卡片。

    与 `sources` 的区别是**出处**：`sources` 是模型自己写的公开依据，
    无法核实；本结构里的每一条都来自本项目知识库中 `is_published` 为真
    的卡片，可以由 id 反查原文（PROJECT_SPEC 第四十七节第 20 项）。
    """

    id: int = Field(..., description="知识卡片 id，可用于跳转详情")
    title: str = Field(..., description="卡片标题")
    summary: str = Field("", description="卡片摘要")
    category_id: int = Field(..., description="所属分类 id")
    risk_level: str = Field(..., description="卡片自身的风险等级")


class ChatResponse(BaseModel):
    """结构化回答（PROJECT_SPEC 第九节）。

    AI 回答不是一段纯文本：风险等级决定展示方式，
    steps 是可以直接照做的动作，warning 在高风险时给出警告。
    """

    question: str = Field(..., description="用户问题（原样回显）")
    category: str | None = Field(None, description="分类名")
    risk_level: str = Field(..., description="low / medium / high", examples=["high"])
    answer: str = Field(..., description="回答正文")
    steps: list[str] = Field(
        default_factory=list,
        description="可执行步骤，高风险时应非空",
    )
    sources: list[str] = Field(
        default_factory=list,
        description="模型给出的公开依据。与 `references` 不同，这一项无法核实",
    )
    references: list[ChatReference] = Field(
        default_factory=list,
        description="检索到的知识库卡片，可能为空（知识库中没有相关内容时）",
    )
    warning: str | None = Field(
        None,
        description="安全警告，medium / high 时应非空",
    )
