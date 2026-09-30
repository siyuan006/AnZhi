"""通用数据结构：统一错误响应与健康检查响应。

对应 docs/API.md 第 1.1、1.2 与第 2 节。
"""

from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field


class ErrorResponse(BaseModel):
    """统一错误响应体（docs/API.md 1.1）。

    全局异常处理器保证**任何**出错路径都返回这个形状，
    前端因此只需要实现一套错误解析逻辑。
    """

    detail: str = Field(..., description="错误说明", examples=["服务器内部错误"])


class HealthResponse(BaseModel):
    """健康检查响应（docs/API.md 第 2 节）。"""

    status: Literal["ok"] = Field("ok", description="服务状态")
    version: str = Field(..., description="后端版本号")
    database: str = Field(
        ...,
        description="数据库状态：connected / error",
        examples=["connected"],
    )
    ai_service: str = Field(
        ...,
        description="AI 服务状态：configured（已配置 Key）/ not_configured",
        examples=["not_configured"],
    )
