"""DeepSeek API 客户端。

职责边界：只负责「把消息发出去、把 JSON 拿回来、把失败分类」。
提示词构造在 `prompts.py`，业务编排在 `chat_service.py`。

密钥安全（PROJECT_SPEC 第三十五、四十六节）：
    - API Key 只从 `settings`（即 backend/.env）读取，本文件不含任何密钥字面量
    - **任何日志、异常消息、响应体都不会带上 Key**
    - 请求头里的 Authorization 不写进任何日志

可测试性：`transport` 参数允许注入 `httpx.MockTransport`，
使测试能在**不联网、不使用真实 Key** 的情况下走完整个请求构造与解析路径。
"""

from __future__ import annotations

import json
import logging

import httpx

from app.config.settings import settings
from app.services.ai.errors import AIFailure, AIServiceError
from app.services.ai.prompts import SYSTEM_PROMPT, build_user_prompt

logger = logging.getLogger("anzhi")

# 回答需要有稳定的措辞，安全领域不适合高随机性
TEMPERATURE = 0.3

# 上限而非目标长度：安全回答本就要求简洁，同时防止个别请求生成超长文本
MAX_TOKENS = 1024


class DeepSeekClient:
    """DeepSeek Chat Completions 的最小封装。"""

    def __init__(
        self,
        *,
        api_key: str | None = None,
        base_url: str | None = None,
        model: str | None = None,
        timeout: float | None = None,
        transport: httpx.AsyncBaseTransport | None = None,
    ) -> None:
        self._api_key = api_key if api_key is not None else settings.deepseek_api_key
        self._base_url = (base_url or settings.deepseek_base_url).rstrip("/")
        self._model = model or settings.deepseek_model
        self._timeout = timeout if timeout is not None else settings.deepseek_timeout
        self._transport = transport

    @property
    def is_configured(self) -> bool:
        return bool(self._api_key)

    async def complete_json(self, message: str, category: str | None = None) -> dict:
        """请求一次回答，返回解析后的 JSON 对象。

        失败一律抛 [AIServiceError]，调用方不需要认识 httpx 的异常体系。
        """
        if not self.is_configured:
            raise AIServiceError(
                AIFailure.NOT_CONFIGURED,
                "AI 服务未配置，请在 backend/.env 中填写 DEEPSEEK_API_KEY 后重启后端",
            )

        payload = {
            "model": self._model,
            "messages": [
                {"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user", "content": build_user_prompt(message, category)},
            ],
            "temperature": TEMPERATURE,
            "max_tokens": MAX_TOKENS,
            "stream": False,
            # 要求上游直接输出 JSON 对象，省去从自然语言里抠 JSON 的脆弱解析
            "response_format": {"type": "json_object"},
        }

        raw = await self._post(payload)
        return self._parse_content(raw)

    # ------------------------------------------------------------------
    # 内部：发请求
    # ------------------------------------------------------------------

    async def _post(self, payload: dict) -> str:
        """发送请求并返回 choices[0].message.content 原始字符串。"""
        headers = {
            "Authorization": f"Bearer {self._api_key}",
            "Content-Type": "application/json",
        }
        url = f"{self._base_url}/chat/completions"

        try:
            async with httpx.AsyncClient(
                timeout=self._timeout, transport=self._transport
            ) as client:
                response = await client.post(url, json=payload, headers=headers)
        except httpx.TimeoutException as exc:
            logger.warning("DeepSeek 请求超时（%s 秒）", self._timeout)
            raise AIServiceError(
                AIFailure.TIMEOUT,
                "AI 服务响应超时，请稍后重试",
                cause=exc,
            ) from exc
        except httpx.HTTPError as exc:
            # 连接失败、DNS 失败、TLS 失败等
            logger.warning("DeepSeek 请求失败：%s", type(exc).__name__)
            raise AIServiceError(
                AIFailure.UPSTREAM_ERROR,
                "无法连接 AI 服务，请检查网络后重试",
                cause=exc,
            ) from exc

        if response.status_code != 200:
            raise self._http_error(response)

        try:
            body = response.json()
            content = body["choices"][0]["message"]["content"]
        except (json.JSONDecodeError, KeyError, IndexError, TypeError) as exc:
            # 不把响应体塞进异常消息：它属于上游实现细节，对用户没有意义
            logger.error(
                "DeepSeek 响应结构异常：%s",
                response.text[:500],
            )
            raise AIServiceError(
                AIFailure.UPSTREAM_ERROR,
                "AI 服务返回了无法识别的内容，请稍后重试",
                cause=exc,
            ) from exc

        if not isinstance(content, str) or not content.strip():
            raise AIServiceError(
                AIFailure.BAD_RESPONSE,
                "AI 服务返回了空回答，请重新提问",
            )
        return content

    def _http_error(self, response: httpx.Response) -> AIServiceError:
        """把上游状态码翻译成失败分类。"""
        status = response.status_code
        logger.error("DeepSeek 返回 %d：%s", status, response.text[:500])

        if status in (401, 403):
            return AIServiceError(
                AIFailure.UNAUTHORIZED,
                "AI 服务鉴权失败，请检查 DEEPSEEK_API_KEY 是否有效",
            )
        if status == 429:
            return AIServiceError(
                AIFailure.RATE_LIMITED,
                "AI 服务当前请求过多或额度不足，请稍后重试",
            )
        if status >= 500:
            return AIServiceError(
                AIFailure.UPSTREAM_ERROR,
                "AI 服务暂时不可用，请稍后重试",
            )
        return AIServiceError(
            AIFailure.UPSTREAM_ERROR,
            f"AI 服务返回异常状态（HTTP {status}）",
        )

    # ------------------------------------------------------------------
    # 内部：解析回答
    # ------------------------------------------------------------------

    def _parse_content(self, content: str) -> dict:
        """把模型输出解析成 JSON 对象。

        即使开了 JSON 模式，模型偶尔仍会包一层 ```json 代码块，
        这里做一次容错剥离 —— 因为为此让用户重问一次是不值得的。
        """
        text = content.strip()
        if text.startswith("```"):
            text = text.strip("`")
            # 去掉可能残留的语言标记，例如 "json\n{...}"
            if "\n" in text:
                first_line, rest = text.split("\n", 1)
                if not first_line.strip().startswith("{"):
                    text = rest
        text = text.strip()

        try:
            parsed = json.loads(text)
        except json.JSONDecodeError as exc:
            logger.error("模型输出不是合法 JSON：%s", content[:500])
            raise AIServiceError(
                AIFailure.BAD_RESPONSE,
                "AI 返回的内容格式不正确，请重新提问",
                cause=exc,
            ) from exc

        if not isinstance(parsed, dict):
            raise AIServiceError(
                AIFailure.BAD_RESPONSE,
                "AI 返回的内容格式不正确，请重新提问",
            )
        return parsed
