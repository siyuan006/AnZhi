"""个性化设置业务逻辑。对应 docs/API.md 第 8 节与 PROJECT_SPEC 第四十二节。

分层（PROJECT_SPEC 第五十二节）：api → services → models，单向。
本模块不认识 HTTP：不接收 Request、不抛 HTTPException，
「这个分类不存在」是业务结果，翻译成 404 是 api 层的事。

V1.0 的个性化只有三件事（PROJECT_SPEC 第四十二节）：
关注分类、显示/隐藏首页模块、通知开关。拖动模块、调整顺序属于未来版本。

## 没见过设置页的用户

`user_settings` 表里只有**写过设置**的用户才有行。绝大多数用户从没打开过
设置页，所以：

    GET  **不建行**，直接返回代码里的默认值
    PUT  才建行，且建行时把没传的字段填成默认值

GET 不写库是有意的：它会被首页每次加载调用，为一个只读请求插一行
纯属浪费；更重要的是 GET 应当是幂等的，不该有副作用。

由此带来一个**很容易踩的坑**：`home_modules` 列的 `server_default` 是
`'[]'`，而「空数组」在本模块的语义是「用户把所有模块都藏起来了」。
如果 PUT 建行时不显式填默认值，一个只想改通知开关的用户
会顺带得到一份「首页什么都不显示」的设置，而且不报任何错。
因此 `_DEFAULT_HOME_MODULES` 在**建行时必须显式写入** —— 见 `update_settings`。

## 数组字段的规范化

`followed_categories` 去重后按 id 升序，`home_modules` 去重后按
`HOME_MODULES` 的固定顺序排列。两个理由：

 · 「关注了消防和反诈」和「关注了反诈和消防」是同一件事，
   存成两种写法只会让下游比较、去重、判断相等时到处出错；
 · 拖动排序是未来版本的事（PROJECT_SPEC 第十九节），
   V1 里数组的顺序不承载任何信息，正好按一个固定规则定死。
"""

from __future__ import annotations

from dataclasses import dataclass

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.category import Category
from app.models.user_settings import UserSettings

#: 首页可显示/隐藏的模块，顺序即首页从上到下的排布（PROJECT_SPEC 第七节）。
#:
#: ⚠️ 这组键是**接口契约**，前端 frontend/lib/core/app_constants.dart 里的
#: `kHomeModules` 必须与之一致，否则设置页改了半天，首页认不出来。
#: 与 `categories.id` 一样，两边对不上时不会有报错，只会「设置无效」。
HOME_MODULES: tuple[str, ...] = (
    "daily",  # 今日安全知识
    "recommend",  # 推荐知识
    "category",  # 安全分类
    "ai",  # AI 助手入口
    "community",  # 社区精选
)

#: 没写过设置的用户看到的首页：全部都显示。
#: 注意它与 `[]` 不是一回事 —— `[]` 表示用户主动关掉了全部模块。
_DEFAULT_HOME_MODULES: tuple[str, ...] = HOME_MODULES

#: `followed_categories` 的长度上限。
#: V1 只有六个分类，这个数字是给恶意/出错客户端兜底的：
#: 不限长的话，一个几万项的数组会被原样拼进 `IN (...)`，
#: 轻则慢查询，重则撞上数据库的参数个数上限变成 500。
MAX_FOLLOWED_CATEGORIES = 100


@dataclass(frozen=True)
class SettingsView:
    """一份可以直接对外返回的设置。

    用独立的值对象而不是 ORM 对象的理由：没写过设置的用户根本没有
    那一行，而接口必须给出结构完全相同的响应。让视图层去处理
    「对象可能是 None」会把默认值逻辑散到调用方。
    """

    followed_categories: tuple[int, ...]
    home_modules: tuple[str, ...]
    notify_enabled: bool


def normalize_categories(category_ids: list[int]) -> tuple[int, ...]:
    """去重并按 id 升序。"""
    return tuple(sorted(set(category_ids)))


def normalize_modules(modules: list[str]) -> tuple[str, ...]:
    """去重并按 `HOME_MODULES` 的固定顺序排列。

    不用 `sorted()`：那会得到字母序，与首页从上到下的顺序无关，
    既不好读，也没法直接拿来渲染。
    """
    wanted = set(modules)
    return tuple(key for key in HOME_MODULES if key in wanted)


def unknown_modules(modules: list[str]) -> list[str]:
    """返回其中无法识别的模块键，保持首次出现的顺序、不重复。

    保持原样返回而不是直接丢掉：静默忽略意味着客户端拼错一个键时
    「保存成功」但首页毫无变化，排查起来毫无线索。
    """
    return [key for key in dict.fromkeys(modules) if key not in HOME_MODULES]


def unknown_category_ids(db: Session, category_ids: list[int]) -> list[int]:
    """返回其中在 `categories` 表里不存在的 id，升序。

    外键是「存的这一行指向的分类还在不在」，管不了「用户关注了一个
    根本不存在的分类」—— 关注关系只是 JSON 数组里的一个数字，
    数据库不会替我们看着。所以每次写入前都要回表确认一次。
    """
    wanted = set(category_ids)
    if not wanted:
        return []

    known = set(db.scalars(select(Category.id).where(Category.id.in_(wanted))).all())
    return sorted(wanted - known)


def _find(db: Session, *, user_id: int) -> UserSettings | None:
    """取某个用户的设置行；没有则返回 None。

    `user_id` 是查询条件的一部分，不是可选的过滤条件 ——
    少了它，任何人都能读到别人的设置。
    """
    return db.scalar(select(UserSettings).where(UserSettings.user_id == user_id))


def _view(row: UserSettings) -> SettingsView:
    return SettingsView(
        followed_categories=tuple(row.followed_categories),
        home_modules=tuple(row.home_modules),
        notify_enabled=row.notify_enabled,
    )


def get_view(db: Session, *, user_id: int) -> SettingsView:
    """读当前设置；没有设置行时返回默认值（**不建行**）。

    默认值就是「全新的用户应该看到什么」：没关注任何分类、
    首页模块全开、通知开着。这样客户端不需要自己判断
    「拿到空对象意味着什么」。
    """
    row = _find(db, user_id=user_id)
    if row is None:
        return SettingsView(
            followed_categories=(),
            home_modules=_DEFAULT_HOME_MODULES,
            notify_enabled=True,
        )
    return _view(row)


def update_settings(
    db: Session,
    *,
    user_id: int,
    followed_categories: list[int] | None = None,
    home_modules: list[str] | None = None,
    notify_enabled: bool | None = None,
) -> SettingsView:
    """更新设置并返回更新后的完整视图。

    **`None` 表示「这次不改这一项」**，而不是「改成空」：

        {"followed_categories": []}   →  一个都不关注了
        {}                            →  关注分类保持原样

    两者必须区分得开，否则用户永远取消不掉最后一个关注分类 ——
    每次保存通知开关都会把他关注的东西清空。

    调用方负责先校验取值合法性（见 `unknown_category_ids` /
    `unknown_modules`）。本函数只认已经确认可用的值，
    这样「校验」和「写入」各自只有一条路径。
    """
    row = _find(db, user_id=user_id)

    if row is None:
        row = UserSettings(
            user_id=user_id,
            followed_categories=list(normalize_categories(followed_categories or [])),
            # 建行时**必须**显式给默认值：列的 server_default 是 '[]'，
            # 那在本模块里表示「所有模块都藏起来」。
            # 只改通知开关的用户会莫名其妙得到一个空首页。
            home_modules=list(
                _DEFAULT_HOME_MODULES
                if home_modules is None
                else normalize_modules(home_modules)
            ),
            notify_enabled=True if notify_enabled is None else notify_enabled,
        )
        db.add(row)
        db.commit()
        db.refresh(row)
        return _view(row)

    if followed_categories is not None:
        row.followed_categories = list(normalize_categories(followed_categories))
    if home_modules is not None:
        row.home_modules = list(normalize_modules(home_modules))
    if notify_enabled is not None:
        row.notify_enabled = notify_enabled

    db.commit()
    db.refresh(row)
    return _view(row)
