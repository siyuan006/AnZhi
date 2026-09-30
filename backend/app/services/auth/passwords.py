"""口令哈希 —— 只进不出。

安全要求（docs/DATABASE.md 3.1 / AI_RULES 第九节）：
    `password_hash` 只允许存放 bcrypt 产生的哈希值，
    禁止存储明文密码，禁止把明文或哈希写进日志。

本模块只做两件事：把口令变成哈希、把口令和哈希做比对。
**不提供任何「还原口令」的能力** —— bcrypt 本身也不具备。
"""

from __future__ import annotations

import bcrypt

# bcrypt 的工作因子。每 +1 计算耗时翻倍。
# 12 是当前的安全默认值：单次约几十毫秒，登录时用户无感，
# 但把离线爆破的成本抬到了不可行的量级。
_BCRYPT_ROUNDS = 12

# bcrypt 算法本身的硬上限：只取前 72 字节参与运算。
#
# ⚠️ 这是**字节**不是字符。UTF-8 下中文一个字占 3 字节，
# 所以 24 个汉字（72 字节）就会触到上限 ——
# 写「密码最长 72 个字符」是错的，会让中文用户撞上一个看不懂的报错。
#
# 更要紧的是：bcrypt 5.x 遇到超长口令会**抛 ValueError 而不是截断**，
# 不拦住就会变成 500。而且「截断」本身就危险 ——
# 两个前 72 字节相同的不同口令会互相能登录。
MAX_PASSWORD_BYTES = 72

MIN_PASSWORD_CHARS = 8


def hash_password(password: str) -> str:
    """把明文口令转成可直接入库的哈希字符串。

    返回的是形如 `$2b$12$...` 的自包含字符串：
    算法、工作因子、盐都编码在里面，因此校验时不需要额外存盐。
    """
    encoded = _encode(password)
    return bcrypt.hashpw(encoded, bcrypt.gensalt(rounds=_BCRYPT_ROUNDS)).decode("ascii")


def verify_password(password: str, password_hash: str) -> bool:
    """校验口令是否与哈希匹配。

    任何异常都返回 False 而不是向上抛：调用方只关心「能不能登录」，
    哈希字段损坏、算法不认识这类情况，结论同样是「不通过」，
    没有理由把一个 500 抛给正在登录的用户。
    """
    try:
        return bcrypt.checkpw(_encode(password), password_hash.encode("ascii"))
    except (ValueError, TypeError, UnicodeEncodeError):
        return False


def _encode(password: str) -> bytes:
    """按 UTF-8 编码。

    UTF-8 在这里是必须的：中文口令用默认编码会直接抛
    UnicodeEncodeError，或者（在别的语言里）按本地编码处理，
    导致同一个口令在不同机器上算出不同哈希。
    """
    return password.encode("utf-8")


def password_problem(password: str) -> str | None:
    """检查口令是否符合规则，返回给用户看的中文说明；合规时返回 None。

    规则写得比「至少 8 位」更具体，是因为含糊的报错会让用户反复试错：

    - **长度按字节算**。中文口令 24 字就到上限，必须说清楚，
      否则用户只会看到「密码不正确」而完全不知道为什么。
    - **不强制大小写数字混合**。强制组合规则会把人逼向
      `Password1` 这类可预测的口令，长度比组合更有价值。
    """
    if len(password) < MIN_PASSWORD_CHARS:
        return f"密码至少 {MIN_PASSWORD_CHARS} 位"

    if len(_encode(password)) > MAX_PASSWORD_BYTES:
        return (
            f"密码过长：最多 {MAX_PASSWORD_BYTES} 字节，"
            "一个汉字占 3 字节（约 24 个汉字）"
        )

    return None
