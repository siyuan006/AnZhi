import 'package:flutter/material.dart';

import '../pages/ai_page.dart';
import '../pages/community_page.dart';
import '../pages/home_page.dart';
import '../pages/knowledge_page.dart';
import '../pages/profile_page.dart';

/// 安知 —— 主框架
///
/// 底部导航固定五项（PROJECT_SPEC 第六节）：
///   首页 / AI / 知识 / 社区 / 我的
///
/// 使用 [IndexedStack] 保留各页面状态，切换标签时不会重建页面、
/// 也不会丢失滚动位置。
class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});

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
          HomePage(onNavigateToTab: _onDestinationSelected),
          const AiPage(),
          const KnowledgePage(),
          const CommunityPage(),
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
