/// 安知 —— 个性化设置
///
/// 字段与 `backend/app/schemas/settings.py` 的 `SettingsOut` 严格对应。
///
/// `GET /api/settings` 与 `PUT /api/settings` 返回**同一个结构**：
/// 保存成功后拿到的是完整的最新设置，设置页据此直接刷新，
/// 不必再发一次 GET。
class UserSettings {
  const UserSettings({
    required this.followedCategories,
    required this.homeModules,
    required this.notifyEnabled,
  });

  /// 关注的分类 id。后端去重后升序返回。
  final List<int> followedCategories;

  /// 首页要显示的模块 id，按首页从上到下的顺序。
  ///
  /// **空列表是有含义的**：表示用户把全部模块都藏起来了。
  /// 它和「从没设置过」（后端返回全部模块）不是一回事 ——
  /// 所以这里不能用「空就当成默认」的兜底，那会让用户关不掉最后一个模块。
  final List<String> homeModules;

  /// 通知开关。
  final bool notifyEnabled;

  bool follows(int categoryId) => followedCategories.contains(categoryId);

  bool showsModule(String moduleId) => homeModules.contains(moduleId);

  factory UserSettings.fromJson(Map<String, dynamic> json) {
    return UserSettings(
      followedCategories: _intList(json['followed_categories']),
      homeModules: _stringList(json['home_modules']),
      notifyEnabled: json['notify_enabled'] as bool? ?? true,
    );
  }

  /// 解析一个 JSON 数组为 int 列表。
  ///
  /// 逐项过滤而不是整体强转：混进一个非数字的脏数据时强转会抛，
  /// 一个字段解析不了不该让整个设置页打不开。
  static List<int> _intList(Object? raw) {
    if (raw is! List) return const <int>[];
    return <int>[
      for (final Object? item in raw)
        if (item is num) item.toInt(),
    ];
  }

  static List<String> _stringList(Object? raw) {
    if (raw is! List) return const <String>[];
    return <String>[
      for (final Object? item in raw)
        if (item is String) item,
    ];
  }
}
