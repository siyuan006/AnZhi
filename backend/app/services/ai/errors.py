"""AI 服务的领域异常。

上层（路由）不需要认识 httpx 的异常类型，也不需要判断「是超时还是 401」，
只需要知道「这次 AI 调用为什么没成功」，因此统一收敛成这一种异常。

`reason` 用枚举而不是自由字符串：路由层要据此决定 HTTP 状态码，
自由字符串很容易因为拼写不一致而静默失配。
"""

from __future__ import annotations

from enum import Enum


class AIFailure(str, Enum):
    """AI 调用失败的原因分类。"""

    NOT_CONFIGURED = "not_configured"
    """没有配置 DEEPSEEK_API_KEY。属于部署问题，不是上游故障。"""

    UNAUTHORIZED = "unauthorized"
    """API Key 无效或已过期。重新生成 Key 或检查余额。"""

    RATE_LIMITED = "rate_limited"
    """触发限流或余额不足。"""

    TIMEOUT = "timeout"
    """超时。"""

    UPSTREAM_ERROR = "upstream_error"
    """上游返回了非预期状态码或无法解析的响应。"""

    BAD_RESPONSE = "bad_response"
    """上游返回了内容，但不符合我们要求的回答结构。"""


class AIServiceError(Exception):
    """AI 服务调用失败。

    `message` 是给用户看的中文说明，本身就是安全的（不含密钥、不含堆栈）。
    原始异常通过 `cause` 保留，只写进服务端日志。
    """

    def __init__(self, reason: AIFailure, message: str, *, cause: Exception | None = None):
        super().__init__(message)
        self.reason = reason
        self.message = message
        self.cause = cause

    def __str__(self) -> str:
        return f"[{self.reason.value}] {self.message}"
