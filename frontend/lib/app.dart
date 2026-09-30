import 'package:flutter/material.dart';

import 'core/app_constants.dart';
import 'core/app_theme.dart';
import 'core/auth_controller.dart';
import 'services/chat_api.dart';
import 'services/knowledge_api.dart';
import 'widgets/main_scaffold.dart';

/// 安知 —— 应用根组件
///
/// 只负责装配全局配置（主题、标题、本地化）与全局状态，
/// 页面结构与业务逻辑分别在 `widgets/main_scaffold.dart` 与 `pages/` 中。
class AnZhiApp extends StatefulWidget {
  const AnZhiApp({
    super.key,
    this.knowledgeApi,
    this.chatApi,
    this.authController,
  });

  /// 知识接口。默认在页面内部自行创建；测试时注入假实现，
  /// 使整个应用可以在无网络环境下被完整驱动。
  final KnowledgeApi? knowledgeApi;

  /// AI 问答接口。同样只在测试时注入。
  final ChatApi? chatApi;

  /// 登录状态。默认自行创建；测试时注入一份连着假后端的实现。
  final AuthController? authController;

  @override
  State<AnZhiApp> createState() => _AnZhiAppState();
}

class _AnZhiAppState extends State<AnZhiApp> {
  late final AuthController _auth = widget.authController ?? AuthController();
  late final bool _ownsAuth = widget.authController == null;

  @override
  void initState() {
    super.initState();
    // 确认本地是否还留着有效的登录凭证。
    // 不在 build 里做：那会在每次重建时重复发请求。
    _auth.restore();
  }

  @override
  void dispose() {
    if (_ownsAuth) _auth.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // AuthScope 放在 MaterialApp **外面**：这样 Navigator 推出来的新路由
    // （登录页、收藏页）也在它的子树里。
    // 放在 home 里的话，push 出去的页面拿不到登录状态。
    return AuthScope(
      controller: _auth,
      child: MaterialApp(
        title: kAppName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: MainScaffold(
          knowledgeApi: widget.knowledgeApi,
          chatApi: widget.chatApi,
        ),
      ),
    );
  }
}
