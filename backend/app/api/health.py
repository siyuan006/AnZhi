"""健康检查路由。

对应 docs/API.md 第 2 节。
"""

from __future__ import annotations

from fastapi import APIRouter

from app import __version__
from app.config.settings import settings
from app.schemas.common import HealthResponse

router = APIRouter(tags=["健康检查"])


@router.get(
    "/api/health",
    response_model=HealthResponse,
    summary="健康检查",
    description="返回服务状态、版本、数据库状态与 AI 服务配置状态。",
)
async def health() -> HealthResponse:
    """检查后端是否正常。

    `database` 目前固定为 `pending`：SQLite 在**第六阶段**接入，
    届时这里会改为真实的数据库连接探测。
    在接入之前谎报 `connected` 属于伪造接口状态，明确禁止。
    """
    return HealthResponse(
        status="ok",
        version=__version__,
        database="pending",
        ai_service="configured" if settings.is_ai_configured else "not_configured",
    )
