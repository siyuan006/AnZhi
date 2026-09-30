import 'package:flutter/material.dart';

import '../core/app_constants.dart';
import '../core/app_theme.dart';

/// 安知 —— 我的页面
///
/// 包含（PROJECT_SPEC 第二十二节）：
///   个人信息 · 学习天数 · 收藏 · 历史记录 · 我的帖子
///   关注领域 · 首页布局 · 通知设置 · 关于安知
///
/// ⚠️ 除「关于安知」外，其余入口的功能将在阶段 11、13 实现，
/// 点击会给出明确的阶段提示。
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackgroundColor,
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          kPagePadding,
          0,
          kPagePadding,
          24,
        ),
        children: <Widget>[
          const _ProfileHeader(),
          const SizedBox(height: 18),
          _MenuGroup(
            items: <_MenuItem>[
              _MenuItem(
                icon: Icons.star_outline_rounded,
                label: '我的收藏',
                stage: '阶段 11',
              ),
              _MenuItem(
                icon: Icons.history_rounded,
                label: '浏览历史',
                stage: '阶段 11',
              ),
              _MenuItem(
                icon: Icons.article_outlined,
                label: '我的帖子',
                stage: '阶段 12',
              ),
            ],
          ),
          const SizedBox(height: 14),
          _MenuGroup(
            items: <_MenuItem>[
              _MenuItem(
                icon: Icons.interests_outlined,
                label: '关注领域',
                stage: '阶段 13',
              ),
              _MenuItem(
                icon: Icons.dashboard_customize_outlined,
                label: '首页布局',
                stage: '阶段 13',
              ),
              _MenuItem(
                icon: Icons.notifications_none_rounded,
                label: '通知设置',
                stage: '阶段 13',
              ),
            ],
          ),
          const SizedBox(height: 14),
          _MenuGroup(
            items: <_MenuItem>[
              _MenuItem(
                icon: Icons.info_outline_rounded,
                label: '关于安知',
                onTap: () => _showAbout(context),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              '安知 v$kAppVersion',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showAbout(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('关于安知'),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '安知 —— $kAppSlogan',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 10),
              Text(
                '面向普通用户和大学生的 AI 安全知识科普应用，'
                '覆盖消防、用电、交通、校园、网络反诈、自然灾害六大领域。',
                style: TextStyle(fontSize: 13.5, height: 1.65),
              ),
              SizedBox(height: 10),
              Text(
                '技术栈：Flutter · FastAPI · SQLite · DeepSeek',
                style: TextStyle(fontSize: 12.5, height: 1.6),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('知道了'),
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// 顶部个人信息
// ---------------------------------------------------------------------------

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: kSurfaceColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              Icons.person_rounded,
              size: 28,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '未登录',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '登录功能将在阶段 11 实现',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          // 学习天数占位
          Column(
            children: <Widget>[
              Text(
                '--',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.primary,
                ),
              ),
              Text(
                '学习天数',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 菜单
// ---------------------------------------------------------------------------

class _MenuItem {
  const _MenuItem({
    required this.icon,
    required this.label,
    this.stage,
    this.onTap,
  });

  final IconData icon;
  final String label;

  /// 功能所属阶段。为 `null` 表示功能已实现
  final String? stage;
  final VoidCallback? onTap;
}

class _MenuGroup extends StatelessWidget {
  const _MenuGroup({required this.items});

  final List<_MenuItem> items;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    // 必须用 Material 而不是带背景色的 Container：
    // ListTile 的水波纹绘制在最近的 Material 祖先上，
    // 若中间夹一层带背景色的 DecoratedBox，点击效果会被遮住
    // （Flutter 会抛出 "ListTile background color or ink splashes may be invisible"）。
    return Material(
      color: kSurfaceColor,
      borderRadius: BorderRadius.circular(kCardRadius),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: <Widget>[
          for (int i = 0; i < items.length; i++) ...<Widget>[
            ListTile(
              leading: Icon(
                items[i].icon,
                size: 21,
                color: theme.colorScheme.primary,
              ),
              title: Text(
                items[i].label,
                style: const TextStyle(fontSize: 14.5),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (items[i].stage != null)
                    Text(
                      items[i].stage!,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  const SizedBox(width: 3),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 19,
                    color: theme.colorScheme.outline,
                  ),
                ],
              ),
              onTap: items[i].onTap ??
                  () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          '「${items[i].label}」将在${items[i].stage}实现',
                        ),
                        behavior: SnackBarBehavior.floating,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
            ),
            if (i != items.length - 1)
              const Divider(height: 1, indent: 54, endIndent: 14),
          ],
        ],
      ),
    );
  }
}
