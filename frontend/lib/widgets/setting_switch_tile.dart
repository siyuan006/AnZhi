import 'package:flutter/material.dart';

import '../core/app_constants.dart';
import '../core/app_theme.dart';

/// 安知 —— 设置页的一行开关
///
/// 「关注领域」与「首页布局」两页共用：都是「一列带说明的开关」，
/// 各写一遍的话，两边的加载态与禁用逻辑迟早会长歪。
///
/// **开关不做本地乐观更新。** 点了之后开关不动，等 POST/PUT 回来
/// 才按服务端给的整份设置重画；期间 [busy] 为 true，开关置灰并显示
/// 一个小转圈。理由与点赞按钮一致：服务端会去重、排序，
/// 本地先翻过去再被服务端纠正，用户会看到开关「弹回来」，
/// 那比等半秒更让人不安。
class SettingSwitchTile extends StatelessWidget {
  const SettingSwitchTile({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.icon,
    this.busy = false,
    this.enabled = true,
  });

  final String title;

  /// 副标题。用来说明「打开这个会发生什么」——
  /// 设置页里一个没有说明的开关等于让用户猜。
  final String? subtitle;

  final IconData? icon;

  final bool value;

  /// 为 `null` 时开关不可点（例如整页还在加载）
  final void Function(bool value)? onChanged;

  /// 这一项正在保存
  final bool busy;

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool tappable = enabled && !busy && onChanged != null;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      leading: icon == null
          ? null
          : Icon(
              icon,
              size: 21,
              color: tappable
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outline,
            ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 14.5,
          color: tappable ? null : theme.colorScheme.outline,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: TextStyle(
                fontSize: 12,
                height: 1.45,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
      trailing: busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            )
          : Switch(
              value: value,
              // 保存中不能重复点：连点两下会发出两个请求，
              // 后回来的那个未必是后发的那个
              onChanged: tappable ? onChanged : null,
            ),
      onTap: tappable ? () => onChanged!(!value) : null,
    );
  }
}

/// 设置页顶部的一段说明。
///
/// 设置页最容易犯的错是「一堆开关，没有一个字解释它们是干什么的」。
class SettingHint extends StatelessWidget {
  const SettingHint({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: kSurfaceColor,
        borderRadius: BorderRadius.circular(kCardRadius),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            Icons.info_outline_rounded,
            size: 16,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                height: 1.6,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
