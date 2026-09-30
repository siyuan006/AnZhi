"""个性化设置相关数据结构。对应 docs/API.md 第 8 节。"""

from __future__ import annotations

from pydantic import BaseModel, Field

from app.services.personalization import settings_service
from app.services.personalization.settings_service import SettingsView


class SettingsOut(BaseModel):
    """`GET /api/settings` 与 `PUT /api/settings` 的响应。

    两个接口**共用同一个结构**：PUT 保存成功后客户端手上要有一份完整的
    当前状态，如果它只回一个 204，设置页就得再发一次 GET 才能把界面刷新对。
    """

    followed_categories: list[int] = Field(
        ..., description="关注的分类 id，去重后升序"
    )
    home_modules: list[str] = Field(
        ..., description="首页要显示的模块键，按首页从上到下的顺序"
    )
    notify_enabled: bool = Field(..., description="通知开关")

    @classmethod
    def from_view(cls, view: SettingsView) -> "SettingsOut":
        """从 service 的值对象构造。

        `SettingsView` 里存的是 tuple（不可变，避免调用方顺手改掉），
        这里转成 list —— JSON 里没有 tuple 这个概念。
        """
        return cls(
            followed_categories=list(view.followed_categories),
            home_modules=list(view.home_modules),
            notify_enabled=view.notify_enabled,
        )


class SettingsUpdate(BaseModel):
    """`PUT /api/settings` 的请求体。

    **三个字段都可选，没传的字段保持原样。**

        {"followed_categories": []}   →  一个都不关注了
        {"followed_categories": [1]}  →  改成只关注 1
        {}                            →  关注分类不动

    区分「空数组」和「没传」靠的是 `[]` 与字段缺失本身 —— 两者混为一谈的话，
    用户永远取消不掉最后一个关注分类：他每保存一次别的开关，
    关注列表就被重新加上一遍，而界面显示「已保存」。

    显式传 `null` 与不传等价，同样按「不改这一项」处理。

    长度上限只加在 `followed_categories` 上：V1 一共就六个分类，
    100 是给异常客户端兜底的（不限长的话几万项会被原样拼进 SQL 的
    `IN (...)`，撞上参数个数上限直接变成 500）。`home_modules` 不需要
    长度上限 —— 不认识的键会被逐个挑出来拒绝，超长数组过不了这一关。
    """

    followed_categories: list[int] | None = Field(
        None,
        max_length=settings_service.MAX_FOLLOWED_CATEGORIES,
        description="关注的分类 id；传空数组表示取消全部关注",
    )
    home_modules: list[str] | None = Field(
        None, description="首页要显示的模块键；传空数组表示一个都不显示"
    )
    notify_enabled: bool | None = Field(None, description="通知开关")
