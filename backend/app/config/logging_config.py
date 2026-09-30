"""日志配置。

单独成文件的两个原因：

1. **Windows 编码问题。** Windows 上标准输出默认使用 GBK(cp936)，
   中文日志一旦被重定向到文件就会变成乱码。这里统一切到 UTF-8；
   若输出目标是真实控制台，Python 走 WriteConsoleW，本身就是 Unicode 安全，
   因此这段代码在两种情况下都不会产生副作用。

2. **日志级别分离。** settings.debug 只用于放大**本项目**的日志，
   不把 asyncio、uvicorn 等第三方库一起拖进 DEBUG 级别，
   否则启动日志会被 "Using proactor" 之类的噪声淹没。
"""

from __future__ import annotations

import logging
import sys

from app.config.settings import settings

LOG_FORMAT = "%(asctime)s | %(levelname)-7s | %(name)s | %(message)s"


def _force_utf8_stdio() -> None:
    """把标准输出 / 标准错误切换到 UTF-8，避免中文日志乱码。"""
    for stream in (sys.stdout, sys.stderr):
        reconfigure = getattr(stream, "reconfigure", None)
        if reconfigure is not None:
            reconfigure(encoding="utf-8", errors="replace")


def setup_logging() -> logging.Logger:
    """初始化日志，返回本项目使用的 logger。"""
    _force_utf8_stdio()

    # 全局保持 INFO：第三方库的 DEBUG 日志对本项目没有价值
    logging.basicConfig(level=logging.INFO, format=LOG_FORMAT)

    logger = logging.getLogger("anzhi")
    logger.setLevel(logging.DEBUG if settings.debug else logging.INFO)
    return logger
