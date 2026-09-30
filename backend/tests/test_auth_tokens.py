"""JWT 签发与解析的测试。

token 是这个项目里唯一一件「拿着它就等于你是某人」的东西，
所以这里除了正常路径，重点测**伪造和篡改能不能被挡住**。
"""

from __future__ import annotations

from datetime import timedelta

import jwt
import pytest

from app.config.settings import settings
from app.database.base import utcnow
from app.services.auth import tokens


class TestRoundTrip:
    def test_token_carries_the_user_id(self):
        token = tokens.create_access_token(42)

        assert tokens.read_user_id(token) == 42

    def test_two_tokens_for_the_same_user_are_valid(self):
        """同一用户重复登录会拿到不同的 token，但两个都该能用。

        （差别在 iat/exp 的时间戳上；这里只断言行为，不依赖具体实现。）
        """
        first = tokens.create_access_token(7)
        second = tokens.create_access_token(7)

        assert tokens.read_user_id(first) == 7
        assert tokens.read_user_id(second) == 7

    def test_token_is_a_jwt_with_three_segments(self):
        token = tokens.create_access_token(1)

        assert token.count(".") == 2


class TestRejectsBadTokens:
    """伪造与篡改 —— 这一类失败必须是「解析不出来」，不能是「解析出别人」。"""

    def test_garbage_is_rejected(self):
        assert tokens.read_user_id("not-a-token") is None

    def test_empty_string_is_rejected(self):
        assert tokens.read_user_id("") is None

    def test_token_signed_with_another_key_is_rejected(self):
        """用别的密钥签出来的 token 必须无效。

        这条挂了意味着任何人都能自己签一个 token 冒充别人。
        """
        # 攻击者当然会挑一把足够长的密钥，这里如实模拟：
        # 拦下它的必须是「密钥不对」，而不是「密钥太短」。
        forged = jwt.encode(
            {"sub": "1", "exp": utcnow() + timedelta(hours=1)},
            "attacker-chosen-key-" + "x" * 40,
            algorithm=settings.jwt_algorithm,
        )

        assert tokens.read_user_id(forged) is None

    def test_unsigned_token_is_rejected(self):
        """`alg: none` 是 JWT 历史上最著名的一类绕过手法。"""
        forged = jwt.encode(
            {"sub": "1", "exp": utcnow() + timedelta(hours=1)},
            key="",
            algorithm="none",
        )

        assert tokens.read_user_id(forged) is None

    def test_expired_token_is_rejected(self):
        expired = jwt.encode(
            {"sub": "1", "exp": utcnow() - timedelta(seconds=1)},
            settings.jwt_secret,
            algorithm=settings.jwt_algorithm,
        )

        assert tokens.read_user_id(expired) is None

    def test_token_without_subject_is_rejected(self):
        no_sub = jwt.encode(
            {"exp": utcnow() + timedelta(hours=1)},
            settings.jwt_secret,
            algorithm=settings.jwt_algorithm,
        )

        assert tokens.read_user_id(no_sub) is None

    def test_token_with_non_numeric_subject_is_rejected(self):
        """`sub` 是字符串塞进去的，但内容必须是数字。

        不检查的话，一个 sub="admin" 的 token 会一路传到 `db.get(User, "admin")`。
        """
        weird = jwt.encode(
            {"sub": "not-a-number", "exp": utcnow() + timedelta(hours=1)},
            settings.jwt_secret,
            algorithm=settings.jwt_algorithm,
        )

        assert tokens.read_user_id(weird) is None

    def test_tampered_payload_is_rejected(self):
        """改动 payload 会破坏签名。"""
        token = tokens.create_access_token(1)
        header, _payload, signature = token.split(".")
        forged_payload = jwt.encode(
            {"sub": "999"}, "x" * 48, algorithm="HS256"
        ).split(".")[1]
        tampered = f"{header}.{forged_payload}.{signature}"

        assert tokens.read_user_id(tampered) is None


class TestPayloadContents:
    def test_token_does_not_leak_username_or_email(self):
        """token 是客户端可读的 base64，不该塞进身份之外的资料。

        放进去等于把这些信息交给了任何拿到 token 的人；
        而且用户改了昵称之后，旧 token 里还是过期的那个。
        """
        token = tokens.create_access_token(1)
        payload = jwt.decode(
            token, settings.jwt_secret, algorithms=[settings.jwt_algorithm]
        )

        assert set(payload) == {"sub", "iat", "exp"}


class TestExpiry:
    def test_expiry_follows_the_configured_setting(self):
        token = tokens.create_access_token(1)
        payload = jwt.decode(
            token, settings.jwt_secret, algorithms=[settings.jwt_algorithm]
        )

        expected = settings.jwt_expire_minutes * 60
        assert abs(payload["exp"] - payload["iat"] - expected) <= 1


@pytest.mark.parametrize("user_id", [1, 2, 999999])
def test_any_positive_id_round_trips(user_id: int):
    assert tokens.read_user_id(tokens.create_access_token(user_id)) == user_id
