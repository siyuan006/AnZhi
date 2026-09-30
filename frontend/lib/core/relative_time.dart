/// 安知 —— 时间解析与相对时间显示
///
/// 只做两件事：把后端的时间戳正确解析成 `DateTime`，
/// 再把它显示成「刚刚 / 12 分钟前 / 3 小时前 / 09-28」。
///
/// 独立成文件是因为这里有一个**容易静默出错**的地方：时区。
/// 见 [parseServerTime]。
library;

/// 把后端返回的时间戳解析成本地时区的 [DateTime]。
///
/// 后端全项目统一使用 **naive UTC**（见 `backend/app/database/base.py`
/// 的 `utcnow`），序列化出来是 `2026-09-30T12:00:00` 这种**不带时区**的形式。
///
/// ⚠️ **Dart 的 `DateTime.parse` 遇到不带时区的字符串会当成「本地时间」**。
/// 直接 parse 的话，UTC+8 的用户在北京时间 20:00 看了一条知识，
/// 后端存的是 12:00 UTC，客户端读出来却是本地时间 12:00 ——
/// 「刚刚看过」会显示成「8 小时前」。
///
/// 这里显式补上 `Z` 声明它是 UTC，再 [DateTime.toLocal] 转换。
/// 漂移不会报错、不会崩溃，只会让时间悄悄偏几个小时，所以宁可写死这一步。
///
/// 解析不了（`null`、空串、格式不对）时返回 `null`，
/// 而不是抛异常 —— 一条时间戳有问题不该让整个列表打不开。
DateTime? parseServerTime(String? raw) {
  if (raw == null || raw.isEmpty) return null;

  // 已经带了时区信息（Z 或 +08:00）就不要重复补
  final bool hasZone =
      raw.endsWith('Z') || raw.endsWith('z') || raw.contains('+');
  final DateTime? parsed = DateTime.tryParse(hasZone ? raw : '${raw}Z');

  return parsed?.toLocal();
}

/// 把时间显示成一句人话。
///
/// [now] 可注入，便于测试断言固定结果；不传则取当前时间。
///
/// 超过一天就不再显示「几天前」而是直接给日期：历史列表里
/// 「23 天前」这种说法既不好换算也不好看，日期更直接。
String formatRelativeTime(DateTime? time, {DateTime? now}) {
  if (time == null) return '';

  final DateTime current = now ?? DateTime.now();
  final Duration diff = current.difference(time);

  // 时钟偏差或服务端时间略快时 diff 会是负数，按「刚刚」处理，
  // 否则会显示成「-3 分钟前」
  if (diff.inMinutes < 1) return '刚刚';
  if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
  if (diff.inDays < 1) return '${diff.inHours} 小时前';
  if (diff.inDays < 7) return '${diff.inDays} 天前';

  final String month = time.month.toString().padLeft(2, '0');
  final String day = time.day.toString().padLeft(2, '0');

  // 跨年了就把年份也带上，否则「01-05」看不出是哪一年
  if (time.year != current.year) return '${time.year}-$month-$day';
  return '$month-$day';
}
