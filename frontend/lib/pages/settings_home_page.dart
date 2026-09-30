import 'package:flutter/material.dart';

import '../core/app_constants.dart';
import '../core/app_theme.dart';
import '../models/user_settings.dart';
import '../services/settings_api.dart';
import '../widgets/setting_switch_tile.dart';
import '../widgets/settings_page_shell.dart';

/// 安知 —— 首页布局（阶段 13b，PROJECT_SPEC 第十九、四十二节）
///
/// 链路：`GET /api/settings` 读，`PUT /api/settings` 写。
///
/// V1.0 只支持**显示 / 隐藏**模块。拖动排序属于未来版本
/// （PROJECT_SPEC 第十九节），所以列表顺序是固定的、不提供拖拽手柄 ——
/// 给一个拖不动的手柄比不给更让人恼火。
class SettingsHomePage extends StatefulWidget {
  const SettingsHomePage({super.key, this.api});

  /// 允许注入，便于测试用假后端替换真实网络
  final SettingsApi? api;

  @override
  State<SettingsHomePage> createState() => _SettingsHomePageState();
}

class _SettingsHomePageState extends State<SettingsHomePage>
    with SettingsPageShell<SettingsHomePage> {
  @override
  SettingsApi? get injectedSettingsApi => widget.api;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackgroundColor,
      appBar: AppBar(title: const Text('首页布局')),
      body: buildSettingsShell(
        loadingMessage: '正在加载首页布局…',
        loginMessage: '首页布局是跟着账号保存的。登录后就能自己决定首页显示什么。',
        builder: _buildList,
      ),
    );
  }

  Widget _buildList(UserSettings settings) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(kPagePadding, 12, kPagePadding, 24),
      children: <Widget>[
        const SettingHint(
          text: '关掉的模块不会出现在首页，但功能本身还在 ——'
              '「安全分类」关掉后仍可从底部「知识」标签进入。',
        ),
        const SizedBox(height: 12),
        Material(
          color: kSurfaceColor,
          borderRadius: BorderRadius.circular(kCardRadius),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: <Widget>[
              for (int i = 0; i < HomeModule.all.length; i++) ...<Widget>[
                _buildRow(settings, HomeModule.all[i]),
                if (i != HomeModule.all.length - 1)
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

  Widget _buildRow(UserSettings settings, HomeModule module) {
    final String key = 'module-${module.id}';

    return SettingSwitchTile(
      icon: _iconOf(module),
      title: module.label,
      value: settings.showsModule(module.id),
      busy: saving.contains(key),
      onChanged: (bool value) => _toggle(settings, module, value),
    );
  }

  static IconData _iconOf(HomeModule module) {
    switch (module.id) {
      case 'daily':
        return Icons.wb_sunny_outlined;
      case 'recommend':
        return Icons.recommend_outlined;
      case 'category':
        return Icons.grid_view_rounded;
      case 'ai':
        return Icons.auto_awesome;
      case 'community':
        return Icons.forum_outlined;
      default:
        return Icons.widgets_outlined;
    }
  }

  /// 开关拨动 → 算出新的模块列表 → 整份发出去。
  ///
  /// 新列表按 `HomeModule.all` 的顺序重建，与后端存下来的规范顺序一致。
  /// 顺序在 V1 里不承载信息，但两端用同一个规则，比对起来才不会出错。
  void _toggle(UserSettings settings, HomeModule module, bool value) {
    final List<String> next = <String>[
      for (final HomeModule item in HomeModule.all)
        if (item.id == module.id ? value : settings.showsModule(item.id))
          item.id,
    ];
    save('module-${module.id}', homeModules: next);
  }

  Widget _buildFooter(UserSettings settings) {
    if (settings.homeModules.isEmpty) {
      // 全部关掉是允许的 —— 用户说了不要，就不该被拦着。
      // 但必须**提前说清楚后果**，而不是等他回到首页看见一片空白。
      return const SettingHint(
        text: '所有模块都关掉了，首页会是空的。'
            '想恢复时回到这里打开任意一个即可，设置本身不会丢。',
      );
    }

    final List<String> names = <String>[
      for (final HomeModule module in HomeModule.all)
        if (settings.showsModule(module.id)) module.label,
    ];

    return SettingHint(text: '首页将按这个顺序显示：${names.join(' → ')}');
  }
}
