"""配置模块 —— 全部可变配置都在这里从环境变量读取。

安全原则（PROJECT_SPEC 第三十五、四十六节 / AI_RULES 第九节）：
    API Key 只允许存在于 backend/.env，永不写入代码、永不提交仓库。
    因此本文件只负责「读取环境变量」，不包含任何密钥字面量。

用法：
    from app.config.settings import settings
    settings.deepseek_model
"""

from __future__ import annotations

import os
from pathlib import Path

from dotenv import load_dotenv

# 本文件路径为 backend/app/config/settings.py
# parents[0]=config  parents[1]=app  parents[2]=backend
BACKEND_DIR: Path = Path(__file__).resolve().parents[2]

# 加载 backend/.env。
# 开发初期允许该文件不存在（此时全部使用下面的默认值），因此不检查返回值。
load_dotenv(BACKEND_DIR / ".env")


def _get_bool(name: str, default: bool) -> bool:
    """把环境变量解析成布尔值，识别 1/true/yes/on（不区分大小写）。"""
    raw = os.getenv(name)
    if raw is None:
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on"}


def _get_int(name: str, default: int) -> int:
    """把环境变量解析成整数；无法解析时回退到默认值，避免启动直接崩溃。"""
    raw = os.getenv(name)
    if raw is None or not raw.strip():
        return default
    try:
        return int(raw.strip())
    except ValueError:
        return default


def _get_list(name: str, default: list[str]) -> list[str]:
    """把逗号分隔的环境变量解析成列表，例如 "a,b" -> ["a", "b"]。"""
    raw = os.getenv(name)
    if not raw or not raw.strip():
        return default
    return [item.strip() for item in raw.split(",") if item.strip()]


class Settings:
    """应用配置对象。

    所有字段都来自环境变量，对应模板见 backend/.env.example。
    在模块底部实例化为单例 `settings`，全项目共用一份。
    """

    def __init__(self) -> None:
        # ---- 应用信息 ----
        self.app_name: str = os.getenv("APP_NAME", "AnZhi")
        self.app_env: str = os.getenv("APP_ENV", "development")
        self.debug: bool = _get_bool("DEBUG", True)
        self.version: str = "1.0.0"

        # ---- 服务监听 ----
        self.host: str = os.getenv("HOST", "0.0.0.0")
        self.port: int = _get_int("PORT", 8000)

        # ---- 数据库（第六阶段接入 SQLite）----
        self.database_url: str = os.getenv("DATABASE_URL", "sqlite:///./anzhi.db")

        # ---- CORS ----
        # Flutter 原生端（Android APK）走的是原生 HTTP，不受浏览器同源策略约束，
        # 因此这里只服务于 Flutter Web 调试与浏览器直接访问 /docs。
        # 开发环境默认放开；生产环境必须显式配置来源。
        default_origins = ["*"] if not self.is_production else []
        self.cors_origins: list[str] = _get_list("CORS_ORIGINS", default_origins)

        # ---- DeepSeek（第八阶段才会真正调用）----
        self.deepseek_api_key: str = os.getenv("DEEPSEEK_API_KEY", "").strip()
        self.deepseek_base_url: str = os.getenv(
            "DEEPSEEK_BASE_URL", "https://api.deepseek.com"
        ).rstrip("/")
        self.deepseek_model: str = os.getenv("DEEPSEEK_MODEL", "deepseek-chat")
        # 大模型生成一段回答通常需要十几秒，超时给得太短会大量误报失败。
        # 但仍必须有上限：没有超时的话，上游卡住会让请求一直挂着。
        self.deepseek_timeout: float = float(_get_int("DEEPSEEK_TIMEOUT", 60))

    @property
    def is_ai_configured(self) -> bool:
        """是否已配置 DeepSeek API Key。

        只检查「有没有填」，**不发起任何真实调用**，避免白白消耗额度。
        """
        return bool(self.deepseek_api_key)

    @property
    def is_production(self) -> bool:
        return self.app_env.strip().lower() in {"production", "prod"}


# 全局单例：其余模块统一 `from app.config.settings import settings`
settings = Settings()
