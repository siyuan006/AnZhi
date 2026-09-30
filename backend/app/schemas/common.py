"""通用数据结构：统一错误响应与健康检查响应。

对应 docs/API.md 第 1.1、1.2 与第 2 节。
"""

from __future__ import annotations

from typing import Generic, Literal, TypeVar

from pydantic import BaseModel, Field

T = TypeVar("T")


class Page(BaseModel, Generic[T]):
    """统一分页响应（docs/API.md 1.3）。

    泛型写法让每个列表接口都能复用同一套分页结构，
    同时保持 `items` 内元素的类型校验。
    """

    total: int = Field(..., description="符合条件的总条数")
    page: int = Field(..., description="当前页码，从 1 开始")
    page_size: int = Field(..., description="每页条数")
    items: list[T] = Field(default_factory=list)


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
