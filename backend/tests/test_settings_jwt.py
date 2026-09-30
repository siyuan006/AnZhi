"""JWT 密钥缺失时的行为。

这是本次改动里唯一一处「主动让程序起不来」的地方，值得单独测：
一个写死的默认密钥会让「登录」这件事看起来是安全的，实际上
任何人都能伪造 token —— 那比明确报错危险得多。
"""

from __future__ import annotations

import pytest

from app.config.settings import Settings


def build(monkeypatch: pytest.MonkeyPatch, env: str, secret: str | None) -> Settings:
    """在指定的环境变量下构造一份全新的配置。

    `settings` 是模块级单例，直接改它会污染同一进程里的其他测试，
    因此这里每次都用 monkeypatch 构造一个新的 Settings 实例。
    """
    monkeypatch.setenv("APP_ENV", env)
    if secret is None:
        monkeypatch.delenv("JWT_SECRET", raising=False)
    else:
        monkeypatch.setenv("JWT_SECRET", secret)
    return Settings()


class TestDevelopment:
    def test_missing_secret_generates_an_ephemeral_one(
        self, monkeypatch: pytest.MonkeyPatch
    ):
        """开发环境不阻塞：随机生成一把，并标记为临时的。"""
        settings = build(monkeypatch, "development", secret=None)

        assert settings.jwt_secret
        assert settings.jwt_secret_is_ephemeral is True

    def test_ephemeral_secrets_differ_between_starts(
        self, monkeypatch: pytest.MonkeyPatch
    ):
        """每次启动一把新密钥 —— 这正是「重启后要重新登录」的原因，
        也是不能拿它当生产密钥的原因。"""
        first = build(monkeypatch, "development", secret=None).jwt_secret
        second = build(monkeypatch, "development", secret=None).jwt_secret

        assert first != second

    def test_configured_secret_is_used_as_is(
        self, monkeypatch: pytest.MonkeyPatch
    ):
        settings = build(monkeypatch, "development", secret="configured-secret")

        assert settings.jwt_secret == "configured-secret"
        assert settings.jwt_secret_is_ephemeral is False

    def test_blank_secret_counts_as_missing(self, monkeypatch: pytest.MonkeyPatch):
        """.env 里写了 `JWT_SECRET=` 是**没配**，不是配了一个空密钥。"""
        settings = build(monkeypatch, "development", secret="   ")

        assert settings.jwt_secret_is_ephemeral is True


class TestProduction:
    def test_missing_secret_refuses_to_start(self, monkeypatch: pytest.MonkeyPatch):
        """生产环境缺密钥直接报错。

        宁可起不来，也不要用一把重启即失效的密钥对外提供登录 ——
        那会让「登录是安全的」变成一个假象。
        """
        with pytest.raises(RuntimeError, match="JWT_SECRET"):
            build(monkeypatch, "production", secret=None)

    def test_prod_alias_also_refuses(self, monkeypatch: pytest.MonkeyPatch):
        """`APP_ENV=prod` 和 `production` 要一视同仁。"""
        with pytest.raises(RuntimeError):
            build(monkeypatch, "prod", secret=None)

    def test_configured_secret_starts_fine(self, monkeypatch: pytest.MonkeyPatch):
        settings = build(monkeypatch, "production", secret="a-real-production-secret")

        assert settings.jwt_secret == "a-real-production-secret"
        assert settings.jwt_secret_is_ephemeral is False

    def test_error_message_does_not_contain_a_secret(
        self, monkeypatch: pytest.MonkeyPatch
    ):
        """报错信息本身不能把密钥带出去 —— 它会进日志。"""
        with pytest.raises(RuntimeError) as excinfo:
            build(monkeypatch, "production", secret=None)

        assert "JWT_SECRET" in str(excinfo.value)
        assert "token_urlsafe" not in str(excinfo.value)
