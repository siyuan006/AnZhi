import 'package:anzhi/core/relative_time.dart';
import 'package:flutter_test/flutter_test.dart';

/// 安知 —— 时间解析与相对时间显示
///
/// 这个文件守的是一个**不会报错、只会悄悄偏几个小时**的坑：
/// 后端统一用 naive UTC，而 `DateTime.parse` 遇到不带时区的字符串
/// 会当成本地时间。写错了不会崩，只会让「刚刚看过」显示成「8 小时前」。
void main() {
  group('parseServerTime', () {
    test('不带时区的时间戳按 UTC 解释', () {
      // 这是后端真实吐出来的格式（pydantic 序列化 naive datetime）
      final DateTime? parsed = parseServerTime('2026-09-30T12:00:00');

      expect(parsed, isNotNull);
      // 关键断言：同一时刻换算到 UTC 必须还是 12:00。
      // 如果按本地时间解析，UTC+8 的机器上这里会变成 04:00。
      expect(parsed!.toUtc(), DateTime.utc(2026, 9, 30, 12, 0, 0));
    });

    test('带 Z 的时间戳同样正确', () {
      final DateTime? parsed = parseServerTime('2026-09-30T12:00:00Z');

      expect(parsed!.toUtc(), DateTime.utc(2026, 9, 30, 12, 0, 0));
    });

    test('带毫秒的格式能解析', () {
      // 后端的时间戳带 6 位小数（微秒），不是 3 位。
      // 注意 Dart 的 `microsecond` 只表示「毫秒之后的那几位」，
      // 不是总微秒数 —— 所以 .123456 是 millisecond=123、microsecond=456。
      final DateTime? parsed = parseServerTime('2026-09-30T12:00:00.123456');

      expect(parsed, isNotNull);
      expect(parsed!.toUtc().hour, 12);
      expect(parsed.toUtc().millisecond, 123);
      expect(parsed.toUtc().microsecond, 456);
    });

    test('返回的是本地时间', () {
      expect(parseServerTime('2026-09-30T12:00:00')!.isUtc, isFalse);
    });

    test('解析不了时返回 null，而不是抛异常', () {
      // 一条时间戳有问题不该让整个列表打不开
      expect(parseServerTime(null), isNull);
      expect(parseServerTime(''), isNull);
      expect(parseServerTime('不是时间'), isNull);
    });
  });

  group('formatRelativeTime', () {
    final DateTime now = DateTime(2026, 9, 30, 20, 0);

    test('一分钟以内是「刚刚」', () {
      expect(
        formatRelativeTime(now.subtract(const Duration(seconds: 30)), now: now),
        '刚刚',
      );
    });

    test('一小时以内显示分钟', () {
      expect(
        formatRelativeTime(now.subtract(const Duration(minutes: 12)), now: now),
        '12 分钟前',
      );
    });

    test('一天以内显示小时', () {
      expect(
        formatRelativeTime(now.subtract(const Duration(hours: 5)), now: now),
        '5 小时前',
      );
    });

    test('一周以内显示天数', () {
      expect(
        formatRelativeTime(now.subtract(const Duration(days: 3)), now: now),
        '3 天前',
      );
    });

    test('超过一周直接给日期', () {
      // 「23 天前」既不好换算也不好看，日期更直接
      expect(
        formatRelativeTime(now.subtract(const Duration(days: 23)), now: now),
        '09-07',
      );
    });

    test('跨年时带上年份', () {
      expect(
        formatRelativeTime(DateTime(2025, 12, 31, 10), now: now),
        '2025-12-31',
      );
    });

    test('时间戳比现在还晚时显示「刚刚」而不是负数', () {
      // 客户端与服务端时钟有偏差时会出现这种情况
      expect(
        formatRelativeTime(now.add(const Duration(minutes: 3)), now: now),
        '刚刚',
      );
    });

    test('时间为 null 时返回空串', () {
      expect(formatRelativeTime(null, now: now), '');
    });
  });
}
