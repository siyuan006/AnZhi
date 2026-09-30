"""健康检查路由。

对应 docs/API.md 第 2 节。
"""

from __future__ import annotations

import logging

from fastapi import APIRouter
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError

from app import __version__
from app.config.settings import settings
from app.database.session import engine
from app.schemas.common import HealthResponse

router = APIRouter(tags=["健康检查"])
logger = logging.getLogger("anzhi")


def _check_database() -> str:
    """探测数据库是否可用。

    只做一次最轻量的 `SELECT 1`，不查业务表 —— 健康检查应当廉价，
    也不应该因为某张表暂时为空就报警。
    """
    try:
        with engine.connect() as connection:
            connection.execute(text("SELECT 1"))
    except SQLAlchemyError:
        logger.exception("数据库健康检查失败")
        return "error"
    return "connected"


@router.get(
    "/api/health",
    response_model=HealthResponse,
    summary="健康检查",
    description="返回服务状态、版本、数据库状态与 AI 服务配置状态。",
)
async def health() -> HealthResponse:
    """检查后端是否正常。

    `database` 是**真实探测结果**，不是写死的常量。
    `ai_service` 只反映「是否已配置 API Key」，不发起真实调用，
    避免健康检查被反复轮询时白白消耗额度。
    """
    return HealthResponse(
        status="ok",
        version=__version__,
        database=_check_database(),
        ai_service="configured" if settings.is_ai_configured else "not_configured",
    )
