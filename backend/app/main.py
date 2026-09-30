"""安知 AnZhi —— FastAPI 应用入口。

本文件只做「装配」：
    创建应用实例 → 注册中间件 → 挂载路由 → 注册全局异常处理。

业务逻辑一律放在 services/ 层，数据模型放在 models/ 层。
不要把业务代码堆进本文件（PROJECT_SPEC 第五十二节 / AI_RULES 第八节）。

启动：
    cd backend
    .venv\\Scripts\\activate
    uvicorn app.main:app --reload
"""

from __future__ import annotations

from contextlib import asynccontextmanager
from typing import AsyncIterator

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app import __version__
from app.api.router import api_router
from app.config.logging_config import setup_logging
from app.config.settings import settings

logger = setup_logging()


@asynccontextmanager
async def lifespan(_app: FastAPI) -> AsyncIterator[None]:
    """应用生命周期：启动时打印配置摘要，停止时记录日志。

    只打印「是否已配置」，**绝不打印 Key 本身**（PROJECT_SPEC 第四十六节）。
    """
    logger.info("安知后端启动中 —— 环境=%s 版本=%s", settings.app_env, settings.version)
    if settings.is_ai_configured:
        logger.info("DeepSeek 已配置：model=%s", settings.deepseek_model)
    else:
        logger.warning(
            "未检测到 DEEPSEEK_API_KEY，AI 问答接口在第八阶段接入前不可用"
            "（复制 backend/.env.example 为 backend/.env 并填写）"
        )
    yield
    logger.info("安知后端已停止")


app = FastAPI(
    title="安知 AnZhi API",
    description="AI 安全知识科普助手 —— 后端接口。交互式文档见 /docs。",
    version=__version__,
    lifespan=lifespan,
)

# CORS：主要服务于浏览器调 /docs 与 Flutter Web 调试。
# Flutter 原生端（Android APK）不受同源策略限制，不依赖这里。
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

# 全部业务路由都从这一处挂载
app.include_router(api_router)


@app.get("/", tags=["健康检查"], summary="服务存活检查")
async def root() -> dict[str, str]:
    """PROJECT_SPEC 第三十二节要求的最小存活检查。"""
    return {"message": "AnZhi API is running"}


# ---------------------------------------------------------------------------
# 全局异常处理
#
# 目标（PROJECT_SPEC 第四十五节 / docs/PRD.md 第 7 节）：
#   任何异常都必须返回统一的 JSON 结构，不允许把堆栈直接抛给客户端，
#   也不允许出现「App 直接崩溃」的体验。
# ---------------------------------------------------------------------------


@app.exception_handler(RequestValidationError)
async def validation_exception_handler(
    _request: Request, exc: RequestValidationError
) -> JSONResponse:
    """把 FastAPI 默认的 422 详情转换成统一错误结构（docs/API.md 1.1）。

    默认结构是嵌套的数组，前端解析麻烦；这里压平成一句可读的说明，
    同时把原始详情放进 `errors` 便于排查。
    """
    first = exc.errors()[0] if exc.errors() else {}
    location = ".".join(str(part) for part in first.get("loc", []) if part != "body")
    message = first.get("msg", "请求参数不合法")
    detail = f"参数校验失败：{location} {message}".strip()

    return JSONResponse(
        status_code=422,
        content={"detail": detail, "errors": exc.errors()},
    )


@app.exception_handler(Exception)
async def unhandled_exception_handler(
    request: Request, exc: Exception
) -> JSONResponse:
    """兜底处理器：未预期的异常统一返回 500，堆栈只写进服务端日志。"""
    logger.exception("未处理的异常：%s %s", request.method, request.url.path)
    return JSONResponse(status_code=500, content={"detail": "服务器内部错误"})
