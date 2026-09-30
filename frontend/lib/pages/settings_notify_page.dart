import 'package:flutter/material.dart';

import '../core/app_constants.dart';
import '../core/app_theme.dart';
import '../models/user_settings.dart';
import '../services/settings_api.dart';
import '../widgets/setting_switch_tile.dart';
import '../widgets/settings_page_shell.dart';

/// 安知 —— 通知设置（阶段 13b，PROJECT_SPEC 第四十二节）
///
/// 链路：`GET /api/settings` 读，`PUT /api/settings` 写。
///
/// ⚠️ **V1.0 还没有通知推送。** 这个开关做的是「把偏好记下来」，
/// 目前没有任何代码读它 —— 所以本页**必须如实说明**，
/// 而不是摆一个看起来在生效的开关。用户以为关掉了推送、
/// 结果将来版本一上线就被打扰，比一开始就说清楚糟糕得多。
class SettingsNotifyPage extends StatefulWidget {
  const SettingsNotifyPage({super.key, this.api});

  /// 允许注入，便于测试用假后端替换真实网络
  final SettingsApi? api;

  @override
  State<SettingsNotifyPage> createState() => _SettingsNotifyPageState();
}

class _SettingsNotifyPageState extends State<SettingsNotifyPage>
    with SettingsPageShell<SettingsNotifyPage> {
  @override
  SettingsApi? get injectedSettingsApi => widget.api;

  /// 这一项在界面上没有「属于哪个分类/模块」的区分，用一个固定键就够了
  static const String _key = 'notify';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackgroundColor,
      appBar: AppBar(title: const Text('通知设置')),
      body: buildSettingsShell(
        loadingMessage: '正在加载通知设置…',
        loginMessage: '通知偏好是跟着账号保存的。登录后就能设置。',
        builder: _buildList,
      ),
    );
  }

  Widget _buildList(UserSettings settings) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(kPagePadding, 12, kPagePadding, 24),
      children: <Widget>[
        Material(
          color: kSurfaceColor,
          borderRadius: BorderRadius.circular(kCardRadius),
          clipBehavior: Clip.antiAlias,
          child: SettingSwitchTile(
            icon: Icons.notifications_none_rounded,
            title: '接收安全提醒',
            value: settings.notifyEnabled,
            busy: saving.contains(_key),
            onChanged: (bool value) => save(_key, notifyEnabled: value),
          ),
        ),
        const SizedBox(height: 16),
        SettingHint(
          text: settings.notifyEnabled
              ? 'V1.0 还没有通知推送功能。现在打开它，表示你希望在功能上线后收到提醒 ——'
                  '偏好已经存下来了，上线时按它执行。'
              : 'V1.0 还没有通知推送功能。现在关掉它，表示你将来也不想收到提醒 ——'
                  '偏好已经存下来了，上线时按它执行。',
        ),
      ],
    );
  }
}
