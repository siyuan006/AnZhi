import 'package:flutter/material.dart';

import 'core/app_constants.dart';
import 'core/app_theme.dart';
import 'widgets/main_scaffold.dart';

/// 安知 —— 应用根组件
///
/// 只负责装配全局配置（主题、标题、本地化），
/// 页面结构与业务逻辑分别在 `widgets/main_scaffold.dart` 与 `pages/` 中。
class AnZhiApp extends StatelessWidget {
  const AnZhiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: kAppName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const MainScaffold(),
    );
  }
}
