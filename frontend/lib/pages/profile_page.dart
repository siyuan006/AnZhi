import 'package:flutter/material.dart';

import '../core/app_constants.dart';
import '../core/app_theme.dart';
import '../core/auth_controller.dart';
import 'favorites_page.dart';
import 'history_page.dart';
import 'login_page.dart';
import 'my_posts_page.dart';
import 'settings_follow_page.dart';
import 'settings_home_page.dart';
import 'settings_notify_page.dart';

/// 安知 —— 我的页面
///
/// 包含（PROJECT_SPEC 第二十二节）：
///   个人信息 · 学习天数 · 收藏 · 历史记录 · 我的帖子
///   关注领域 · 首页布局 · 通知设置 · 关于安知
///
/// 除「关于安知」外**每一栏都需要登录**，因此统一走 [_openAfterLogin]：
/// 未登录时先推登录页，登录成功就顺势把目标页打开 ——
/// 用户点的是「我的收藏」，意图是明确的，不该让他回来再点一次。
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
                onTap: () => _openFavorites(context),
              ),
              _MenuItem(
                icon: Icons.history_rounded,
                label: '浏览历史',
                onTap: () => _openHistory(context),
              ),
              _MenuItem(
                icon: Icons.article_outlined,
                label: '我的帖子',
                onTap: () => _openMyPosts(context),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _MenuGroup(
            items: <_MenuItem>[
              _MenuItem(
                icon: Icons.interests_outlined,
                label: '关注领域',
                onTap: () => _openFollow(context),
              ),
              _MenuItem(
                icon: Icons.dashboard_customize_outlined,
                label: '首页布局',
                onTap: () => _openHomeLayout(context),
              ),
              _MenuItem(
                icon: Icons.notifications_none_rounded,
                label: '通知设置',
                onTap: () => _openNotify(context),
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

  /// 打开「我的收藏」「浏览历史」这类**需要登录**的页面。
  ///
  /// 未登录时**先推登录页，登录成功就顺势把目标页打开** ——
  /// 用户点的是「我的收藏」，意图是明确的，不该让他回来再点一次。
  Future<void> _openAfterLogin(
    BuildContext context,
    Widget Function() page,
  ) async {
    final AuthController? auth = AuthScope.maybeOf(context);
    if (auth == null) return;

    if (!auth.isLoggedIn) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(builder: (_) => const LoginPage()),
      );
      // 用户可能是直接返回、没登录就走了
      if (!context.mounted || !auth.isLoggedIn) return;
    }

    if (!context.mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => page()),
    );
  }

  Future<void> _openFavorites(BuildContext context) =>
      _openAfterLogin(context, () => const FavoritesPage());

  Future<void> _openHistory(BuildContext context) =>
      _openAfterLogin(context, () => const HistoryPage());

  Future<void> _openMyPosts(BuildContext context) =>
      _openAfterLogin(context, () => const MyPostsPage());

  Future<void> _openFollow(BuildContext context) =>
      _openAfterLogin(context, () => const SettingsFollowPage());

  Future<void> _openHomeLayout(BuildContext context) =>
      _openAfterLogin(context, () => const SettingsHomePage());

  Future<void> _openNotify(BuildContext context) =>
      _openAfterLogin(context, () => const SettingsNotifyPage());

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
    // 跟着 AuthController 变化重建：登录 / 登出后这里要立刻换形态
    final AuthController? auth = AuthScope.maybeOf(context);

    final bool loggedIn = auth?.isLoggedIn ?? false;

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
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: loggedIn
                ? Text(
                    auth!.user!.initial,
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.primary,
                    ),
                  )
                : Icon(
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
                  loggedIn ? auth!.user!.displayName : '未登录',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  // 刻意说明「不登录也能查知识」：
                  // 否则用户会以为必须注册才能用这个 App
                  loggedIn
                      ? '@${auth!.user!.username}'
                      : '登录后可以收藏知识、保留浏览历史',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _HeaderAction(auth: auth),
        ],
      ),
    );
  }
}

/// 登录 / 登出按钮。
class _HeaderAction extends StatelessWidget {
  const _HeaderAction({this.auth});

  final AuthController? auth;

  @override
  Widget build(BuildContext context) {
    // 没有 AuthScope（例如单页测试）时整个按钮不显示，
    // 而不是显示一个点了会崩的按钮
    if (auth == null) return const SizedBox.shrink();

    if (!auth!.isLoggedIn) {
      return FilledButton(
        onPressed: () => Navigator.of(context).push<bool>(
          MaterialPageRoute<bool>(builder: (_) => const LoginPage()),
        ),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          minimumSize: const Size(0, 36),
          visualDensity: VisualDensity.compact,
        ),
        child: const Text('登录', style: TextStyle(fontSize: 13.5)),
      );
    }

    return TextButton(
      onPressed: () => _confirmLogout(context, auth!),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        minimumSize: const Size(0, 36),
        visualDensity: VisualDensity.compact,
      ),
      child: const Text('退出', style: TextStyle(fontSize: 13.5)),
    );
  }

  /// 登出前问一句 —— 这是个不可撤销的操作（本地 token 会被清掉）。
  Future<void> _confirmLogout(BuildContext context, AuthController auth) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('退出登录'),
          content: const Text('退出后需要重新输入用户名和密码。'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('退出'),
            ),
          ],
        );
      },
    );

    if (confirmed ?? false) await auth.logout();
  }
}

// ---------------------------------------------------------------------------
// 菜单
// ---------------------------------------------------------------------------

class _MenuItem {
  const _MenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
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
              trailing: Icon(
                Icons.chevron_right_rounded,
                size: 19,
                color: theme.colorScheme.outline,
              ),
              onTap: items[i].onTap,
            ),
            if (i != items.length - 1)
              const Divider(height: 1, indent: 54, endIndent: 14),
          ],
        ],
      ),
    );
  }
}
