"""口令哈希与强度校验的测试。

这一层出错的后果和别的模块不同：别的模块写错了功能会坏，
这里写错了**用户的密码就不安全了**，而且不会有任何报错。
"""

from __future__ import annotations

import pytest

from app.services.auth import passwords


class TestHashing:
    def test_hash_is_not_the_password(self):
        """入库的绝不能是明文 —— 这是整条链路的底线。"""
        hashed = passwords.hash_password("hunter2hunter2")

        assert hashed != "hunter2hunter2"
        assert "hunter2hunter2" not in hashed

    def test_hash_is_bcrypt(self):
        """哈希里要能看出算法与工作因子，换算法时才不至于两眼一抹黑。"""
        hashed = passwords.hash_password("hunter2hunter2")

        assert hashed.startswith("$2b$12$")

    def test_same_password_hashes_differently(self):
        """同样的口令两次结果必须不同。

        相同就说明没加盐 —— 那样攻击者可以拿一张彩虹表
        一次性还原出所有「密码相同」的用户。
        """
        first = passwords.hash_password("hunter2hunter2")
        second = passwords.hash_password("hunter2hunter2")

        assert first != second

    def test_verify_accepts_correct_password(self):
        hashed = passwords.hash_password("hunter2hunter2")

        assert passwords.verify_password("hunter2hunter2", hashed) is True

    def test_verify_rejects_wrong_password(self):
        hashed = passwords.hash_password("hunter2hunter2")

        assert passwords.verify_password("hunter2hunter3", hashed) is False

    def test_verify_rejects_empty_password(self):
        hashed = passwords.hash_password("hunter2hunter2")

        assert passwords.verify_password("", hashed) is False

    def test_verify_is_case_sensitive(self):
        hashed = passwords.hash_password("Hunter2Hunter2")

        assert passwords.verify_password("hunter2hunter2", hashed) is False

    def test_chinese_password_round_trips(self):
        """中文口令必须能存能验。

        用默认编码而不是 UTF-8 的话，这里会直接抛 UnicodeEncodeError ——
        中文用户连注册都过不去。
        """
        secret = "我的安全密码很长"
        hashed = passwords.hash_password(secret)

        assert passwords.verify_password(secret, hashed) is True
        assert passwords.verify_password("我的安全密码很短", hashed) is False

    def test_leading_and_trailing_spaces_are_significant(self):
        """口令里的空格是口令的一部分，不能被悄悄 trim 掉。

        顺手 trim 会让「abc 123」和「abc123」变成同一个密码，
        用户以为自己设了个带空格的强密码，实际并没有。
        """
        hashed = passwords.hash_password("  spaced  ")

        assert passwords.verify_password("  spaced  ", hashed) is True
        assert passwords.verify_password("spaced", hashed) is False

    @pytest.mark.parametrize(
        "broken_hash",
        ["", "not-a-hash", "$2b$12$tooshort", "$$$$"],
    )
    def test_verify_returns_false_on_broken_hash(self, broken_hash: str):
        """哈希字段损坏时返回 False 而不是抛异常。

        调用方只关心「能不能登录」。把 ValueError 抛给正在登录的用户，
        只会变成一个 500，而他照样登不进去。
        """
        assert passwords.verify_password("hunter2hunter2", broken_hash) is False


class TestByteLimit:
    """72 字节上限 —— 这个模块里最容易踩、也最难自己发现的一处。

    踩中时的表现是「注册直接 500」，而用户完全不知道自己哪里错了，
    因为他的密码看起来只有二十几个字。
    """

    def test_chinese_password_counts_as_three_bytes(self):
        """24 个字 = 72 字节：字符数和字节数在这里正好分道扬镳。"""
        assert len("安" * 24) == 24
        assert len(("安" * 24).encode("utf-8")) == 72

    def test_ascii_password_of_72_chars_is_allowed(self):
        assert passwords.password_problem("a" * 72) is None

    def test_73_ascii_chars_is_rejected(self):
        problem = passwords.password_problem("a" * 73)

        assert problem is not None
        assert "过长" in problem

    def test_25_chinese_chars_is_rejected(self):
        """24 个汉字 OK，25 个就超了 —— 按字符数限制就会漏掉这种情况。"""
        assert passwords.password_problem("安" * 24) is None

        problem = passwords.password_problem("安" * 25)
        assert problem is not None
        assert "汉字" in problem, "报错必须说明汉字按 3 字节算，否则用户看不懂"

    def test_hashing_a_too_long_password_raises_so_we_must_validate_first(self):
        """记录 bcrypt 5.x 的真实行为：超长口令是**抛错**而不是静默截断。

        截断本身也是危险的 —— 两个前 72 字节相同的不同口令会互相能登录。
        这条测试的作用是：一旦哪天 bcrypt 改成静默截断，这里会失败，
        提醒我们「不校验也不会报错」这个前提变了。
        """
        with pytest.raises(ValueError):
            passwords.hash_password("a" * 100)


class TestPasswordRules:
    def test_too_short_is_rejected(self):
        problem = passwords.password_problem("abc123")

        assert problem is not None
        assert "8" in problem

    def test_eight_chars_is_the_boundary(self):
        assert passwords.password_problem("a" * 7) is not None
        assert passwords.password_problem("a" * 8) is None

    def test_reason_is_in_chinese_and_actionable(self):
        """报错要能直接展示给用户 —— 含糊的提示只会让人反复试错。"""
        problem = passwords.password_problem("abc")

        assert problem is not None
        assert problem.isascii() is False

    def test_no_composition_rules(self):
        """不强制大小写数字混合。

        强制组合会把人逼向 `Password1` 这类可预测的口令，
        长度比字符种类更有价值。
        """
        assert passwords.password_problem("aaaaaaaa") is None
        assert passwords.password_problem("12345678") is None

    def test_spaces_are_allowed_in_passwords(self):
        """口令短语（passphrase）是更强的选择，不该被规则挡在门外。"""
        assert passwords.password_problem("my dog is very safe") is None
