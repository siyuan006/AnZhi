import 'package:flutter/material.dart';

import '../core/app_constants.dart';
import '../core/app_theme.dart';
import '../models/user_settings.dart';
import '../services/settings_api.dart';
import '../widgets/setting_switch_tile.dart';
import '../widgets/settings_page_shell.dart';

/// 安知 —— 关注领域（阶段 13b，PROJECT_SPEC 第四十二节）
///
/// 链路：`GET /api/settings` 读，`PUT /api/settings` 写。
///
/// 分类列表取自本地常量 `kCategories`，与数据库种子数据一一对应 ——
/// 接口返回的是 id 数组，图标和配色无法由 JSON 表达。
///
/// **关注了之后会发生什么，本页必须说清楚。** 一个不解释自己作用的开关
/// 等于让用户猜；而他猜错之后只会觉得「这个 App 没用」。
class SettingsFollowPage extends StatefulWidget {
  const SettingsFollowPage({super.key, this.api});

  /// 允许注入，便于测试用假后端替换真实网络
  final SettingsApi? api;

  @override
  State<SettingsFollowPage> createState() => _SettingsFollowPageState();
}

class _SettingsFollowPageState extends State<SettingsFollowPage>
    with SettingsPageShell<SettingsFollowPage> {
  @override
  SettingsApi? get injectedSettingsApi => widget.api;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackgroundColor,
      appBar: AppBar(title: const Text('关注领域')),
      body: buildSettingsShell(
        loadingMessage: '正在加载关注设置…',
        loginMessage: '关注领域是跟着账号保存的。登录后就能设置你关心的方向。',
        builder: _buildList,
      ),
    );
  }

  Widget _buildList(UserSettings settings) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(kPagePadding, 12, kPagePadding, 24),
      children: <Widget>[
        const SettingHint(
          text: '关注之后，首页的「推荐知识」会优先给出这些方向的内容。'
              '不关注也能正常浏览全部知识 —— 这只是调整先看到什么。',
        ),
        const SizedBox(height: 12),
        Material(
          color: kSurfaceColor,
          borderRadius: BorderRadius.circular(kCardRadius),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: <Widget>[
              for (int i = 0; i < kCategories.length; i++) ...<Widget>[
                _buildRow(settings, kCategories[i]),
                if (i != kCategories.length - 1)
                  const Divider(height: 1, indent: 50, endIndent: 14),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildFooter(settings),
      ],
    );
  }

  Widget _buildRow(UserSettings settings, SafetyCategory category) {
    final String key = 'category-${category.id}';

    return SettingSwitchTile(
      icon: category.icon,
      title: category.name,
      subtitle: category.description,
      value: settings.follows(category.id),
      busy: saving.contains(key),
      onChanged: (bool value) => _toggle(settings, category, value),
    );
  }

  /// 开关拨动 → 算出新的关注列表 → 整份发出去。
  ///
  /// 发的是**算好的完整数组**而不是「加一个/减一个」的增量：
  /// 后端存的是整份列表，增量接口一旦丢包重试就会加两次。
  void _toggle(UserSettings settings, SafetyCategory category, bool value) {
    final List<int> next = <int>[
      for (final int id in settings.followedCategories)
        if (value || id != category.id) id,
      if (value) category.id,
    ];
    save(
      'category-${category.id}',
      // 注意这里绝不能写成 `next.isEmpty ? null : next`：
      // 空数组表示「取消全部关注」，null 表示「不改」——
      // 混为一谈的话，最后一个关注永远取消不掉。
      followedCategories: next,
    );
  }

  Widget _buildFooter(UserSettings settings) {
    if (settings.followedCategories.isEmpty) {
      return const SettingHint(
        text: '当前没有关注任何领域，首页会按常规顺序推荐内容。',
      );
    }

    final List<String> names = <String>[
      for (final int id in settings.followedCategories)
        categoryById(id)?.name ?? '$id',
    ];

    return SettingHint(text: '已关注：${names.join('、')}');
  }
}
