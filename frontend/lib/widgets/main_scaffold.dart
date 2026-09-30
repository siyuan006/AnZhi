import 'package:flutter/material.dart';

import '../pages/ai_page.dart';
import '../pages/community_page.dart';
import '../pages/home_page.dart';
import '../pages/knowledge_page.dart';
import '../pages/profile_page.dart';
import '../services/chat_api.dart';
import '../services/knowledge_api.dart';
import '../services/post_api.dart';

/// 安知 —— 主框架
///
/// 底部导航固定五项（PROJECT_SPEC 第六节）：
///   首页 / AI / 知识 / 社区 / 我的
///
/// 使用 [IndexedStack] 保留各页面状态，切换标签时不会重建页面、
/// 也不会丢失滚动位置。
class MainScaffold extends StatefulWidget {
  const MainScaffold({
    super.key,
    this.knowledgeApi,
    this.chatApi,
    this.postApi,
  });

  /// 知识接口。为 `null` 时由各页面自行创建（生产路径）；
  /// 测试注入假实现后，无需后端即可驱动整套页面。
  final KnowledgeApi? knowledgeApi;

  /// AI 问答接口。为 `null` 时由 AI 页自行创建（生产路径）。
  final ChatApi? chatApi;

  /// 社区接口。读匿名、写带鉴权，因此这个实例必须由
  /// `AuthController` 那一侧构造好再传进来 —— 见 `app.dart`。
  final PostApi? postApi;

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  int _currentIndex = 0;

  /// 底部导航项定义。顺序即 [IndexedStack] 中页面的顺序，两者必须一致。
  static const List<_NavItem> _navItems = <_NavItem>[
    _NavItem(
      label: '首页',
      icon: Icons.home_outlined,
      selectedIcon: Icons.home_rounded,
    ),
    _NavItem(
      label: 'AI',
      icon: Icons.auto_awesome_outlined,
      selectedIcon: Icons.auto_awesome,
    ),
    _NavItem(
      label: '知识',
      icon: Icons.menu_book_outlined,
      selectedIcon: Icons.menu_book_rounded,
    ),
    _NavItem(
      label: '社区',
      icon: Icons.forum_outlined,
      selectedIcon: Icons.forum_rounded,
    ),
    _NavItem(
      label: '我的',
      icon: Icons.person_outline_rounded,
      selectedIcon: Icons.person_rounded,
    ),
  ];

  /// 允许其他页面通过回调跳转到指定标签。
  void _onDestinationSelected(int index) {
    if (index == _currentIndex) return;
    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: <Widget>[
          HomePage(
            onNavigateToTab: _onDestinationSelected,
            isActive: _currentIndex == 0,
            api: widget.knowledgeApi,
          ),
          AiPage(api: widget.chatApi),
          KnowledgePage(api: widget.knowledgeApi),
          CommunityPage(api: widget.postApi),
          const ProfilePage(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: _onDestinationSelected,
        destinations: <Widget>[
          for (final _NavItem item in _navItems)
            NavigationDestination(
              icon: Icon(item.icon),
              selectedIcon: Icon(item.selectedIcon),
              label: item.label,
            ),
        ],
      ),
    );
  }
}

/// 底部导航项配置
class _NavItem {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}
