import 'package:flutter/material.dart';

import 'core/app_constants.dart';
import 'core/app_theme.dart';
import 'services/chat_api.dart';
import 'services/knowledge_api.dart';
import 'widgets/main_scaffold.dart';

/// 安知 —— 应用根组件
///
/// 只负责装配全局配置（主题、标题、本地化），
/// 页面结构与业务逻辑分别在 `widgets/main_scaffold.dart` 与 `pages/` 中。
class AnZhiApp extends StatelessWidget {
  const AnZhiApp({super.key, this.knowledgeApi, this.chatApi});

  /// 知识接口。默认在页面内部自行创建；测试时注入假实现，
  /// 使整个应用可以在无网络环境下被完整驱动。
  final KnowledgeApi? knowledgeApi;

  /// AI 问答接口。同样只在测试时注入。
  final ChatApi? chatApi;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: kAppName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: MainScaffold(knowledgeApi: knowledgeApi, chatApi: chatApi),
    );
  }
}
