"""AI 问答相关数据结构。对应 docs/API.md 第 3 节与 PROJECT_SPEC 第九节。"""

from __future__ import annotations

from pydantic import BaseModel, Field, field_validator

# 多轮上下文的约束
MAX_HISTORY_ITEMS = 6
MAX_HISTORY_ITEM_LENGTH = 500

# 用户问题的长度上限
MAX_MESSAGE_LENGTH = 1000
MAX_CATEGORY_LENGTH = 50


class ChatRequest(BaseModel):
    """`POST /api/chat` 请求体。"""

    message: str = Field(
        ...,
        description="用户问题，最长 1000 个字",
        examples=["宿舍发生火灾怎么办？"],
    )
    category: str | None = Field(
        None,
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
        """校验用户问题：先去掉首尾空白，再判空与长度。

        长度不写成 `Field(max_length=…)`（`post.py` 里写了同样的理由）：
        那条约束作用在**原始值**上，且在 validator **之前**执行，
        于是「两个空格 + 正好 1000 个字 + 两个空格」会被判超长，
        而用户看到的明明没超。报错文案也只会是英文的
        「String should have at most 1000 characters」——
        客户端是**原样展示**这句话的（docs/API.md 第 3 节的 422 一行），
        等于把一个英文报错摆到用户面前。
        """
        stripped = value.strip()
        if not stripped:
            raise ValueError("问题不能为空")
        if len(stripped) > MAX_MESSAGE_LENGTH:
            raise ValueError(f"问题最长 {MAX_MESSAGE_LENGTH} 个字")
        return stripped

    @field_validator("category")
    @classmethod
    def _category_length(cls, value: str | None) -> str | None:
        """分类同样要给出中文报错，理由同上。"""
        if value is None:
            return None
        stripped = value.strip()
        if len(stripped) > MAX_CATEGORY_LENGTH:
            raise ValueError(f"分类最长 {MAX_CATEGORY_LENGTH} 个字")
        return stripped or None

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
