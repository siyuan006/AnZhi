"""AI 问答路由。对应 docs/API.md 第 3 节。

本层只做三件事：解析参数 → 调用 service → 把失败翻译成状态码。
"""

from __future__ import annotations

import logging

from fastapi import APIRouter, Depends, HTTPException, status

from app.schemas.chat import ChatRequest, ChatResponse
from app.schemas.common import ErrorResponse
from app.services.ai.chat_service import ChatService
from app.services.ai.errors import AIFailure, AIServiceError

logger = logging.getLogger("anzhi")

router = APIRouter(tags=["AI 问答"])


def get_chat_service() -> ChatService:
    """构造问答服务。

    做成依赖项而不是在函数体里直接 new，是为了让测试能用
    `app.dependency_overrides` 换成假的 DeepSeek 客户端 ——
    否则测试要么打真实 API（花钱、不稳定），要么只能测到「未配置」这一条路径。
    """
    return ChatService()

# 失败分类 → HTTP 状态码。
# 「未配置」用 503 而不是 500：这是部署状态问题，
# 客户端据此可以提示「服务端还没配好」，而不是「服务器崩了」。
STATUS_BY_FAILURE: dict[AIFailure, int] = {
    AIFailure.NOT_CONFIGURED: status.HTTP_503_SERVICE_UNAVAILABLE,
    AIFailure.UNAUTHORIZED: status.HTTP_503_SERVICE_UNAVAILABLE,
    AIFailure.RATE_LIMITED: status.HTTP_503_SERVICE_UNAVAILABLE,
    AIFailure.TIMEOUT: status.HTTP_504_GATEWAY_TIMEOUT,
    AIFailure.UPSTREAM_ERROR: status.HTTP_502_BAD_GATEWAY,
    AIFailure.BAD_RESPONSE: status.HTTP_502_BAD_GATEWAY,
}


@router.post(
    "/api/chat",
    response_model=ChatResponse,
    summary="AI 安全问答",
    responses={
        502: {"model": ErrorResponse, "description": "上游 AI 返回异常"},
        503: {"model": ErrorResponse, "description": "AI 服务未配置或不可用"},
        504: {"model": ErrorResponse, "description": "AI 服务超时"},
    },
)
async def chat(
    payload: ChatRequest,
    service: ChatService = Depends(get_chat_service),
) -> ChatResponse:
    """向 DeepSeek 提问并返回结构化回答。

    **安全说明：** 回答由 DeepSeek 生成，当前只经过结构性校验
    （字段是否齐全、风险等级是否可识别、中高风险是否带警告）。
    PROJECT_SPEC 第三十七节要求的 SafetyGuard 内容审查属于阶段 9，
    在那之前**不应把本接口的输出当作已通过安全审查的结论**。
    """
    try:
        return await service.ask(
            message=payload.message,
            category=payload.category,
            history=payload.history,
        )
    except AIServiceError as exc:
        # 只把面向用户的说明返回给客户端；
        # 原始异常（可能含上游响应片段）留在服务端日志里
        logger.warning("AI 问答失败：%s", exc)
        if exc.cause is not None:
            logger.debug("失败原因", exc_info=exc.cause)
        raise HTTPException(
            status_code=STATUS_BY_FAILURE.get(
                exc.reason, status.HTTP_500_INTERNAL_SERVER_ERROR
            ),
            detail=exc.message,
        ) from exc
