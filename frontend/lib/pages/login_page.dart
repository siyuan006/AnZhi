import 'package:flutter/material.dart';

import '../core/app_constants.dart';
import '../core/app_theme.dart';
import '../core/auth_controller.dart';

/// 安知 —— 登录 / 注册
///
/// 两种模式共用一页：字段完全一样（用户名 + 密码，注册多一个昵称），
/// 拆成两个页面会让「我到底该点哪个」变成一道多余的选择题。
///
/// ⚠️ **本页不会保存密码。** `_passwordController` 的内容只在提交那一刻
/// 被读走，随后随页面一起销毁；不写进任何全局状态、不落盘、不打日志。
///
/// 关于注册规则：**不在客户端复述一遍**。
/// 「至少 8 位」「不能超过 72 字节」这类规则由后端判定并返回中文说明，
/// 客户端照原样显示即可 —— 两处各写一份，迟早会不一致，
/// 而用户看到的是两份互相矛盾的提示。
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _nicknameController = TextEditingController();

  /// `false` = 登录，`true` = 注册
  bool _registerMode = false;
  bool _submitting = false;
  String? _error;
  bool _obscure = true;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _nicknameController.dispose();
    super.dispose();
  }

  void _switchMode() {
    if (_submitting) return;
    setState(() {
      _registerMode = !_registerMode;
      // 切换模式时清掉上一条错误：那是针对另一种操作的提示，
      // 留在原地会让人以为当前这个表单也有问题
      _error = null;
    });
  }

  Future<void> _submit() async {
    final AuthController? auth = AuthScope.maybeOf(context);
    if (auth == null || _submitting) return;

    final String username = _usernameController.text.trim();
    final String password = _passwordController.text;

    // 只做「空着没填」这一种本地检查，其余交给后端。
    // 空值检查放这里是为了省一次必然失败的往返。
    if (username.isEmpty || password.isEmpty) {
      setState(() => _error = '用户名和密码都要填');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    final String? problem = _registerMode
        ? await auth.register(
            username: username,
            password: password,
            nickname: _nicknameController.text.trim(),
          )
        : await auth.login(username: username, password: password);

    if (!mounted) return;

    if (problem != null) {
      setState(() {
        _submitting = false;
        _error = problem;
      });
      return;
    }

    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      backgroundColor: kBackgroundColor,
      appBar: AppBar(title: Text(_registerMode ? '注册' : '登录')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(kPagePadding, 12, kPagePadding, 24),
        children: <Widget>[
          Text(
            _registerMode ? '创建一个安知账号' : '登录安知',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _registerMode
                ? '登录后才能收藏知识、保留浏览历史'
                : '登录后可以收藏知识、保留浏览历史',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),

          TextField(
            controller: _usernameController,
            enabled: !_submitting,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: '用户名',
              prefixIcon: Icon(Icons.person_outline_rounded, size: 20),
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 14),

          TextField(
            controller: _passwordController,
            enabled: !_submitting,
            obscureText: _obscure,
            autocorrect: false,
            // 关闭输入法的记忆与建议：口令不该进入输入法词库
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: '密码',
              prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscure
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 19,
                ),
                tooltip: _obscure ? '显示密码' : '隐藏密码',
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            textInputAction:
                _registerMode ? TextInputAction.next : TextInputAction.done,
            onSubmitted: (_) {
              if (!_registerMode) _submit();
            },
          ),

          if (_registerMode) ...<Widget>[
            const SizedBox(height: 14),
            TextField(
              controller: _nicknameController,
              enabled: !_submitting,
              decoration: const InputDecoration(
                labelText: '昵称（可留空）',
                prefixIcon: Icon(Icons.badge_outlined, size: 20),
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
            ),
          ],

          if (_error != null) ...<Widget>[
            const SizedBox(height: 14),
            _ErrorBanner(message: _error!),
          ],

          const SizedBox(height: 22),
          SizedBox(
            height: 48,
            child: FilledButton(
              // 提交中置空 onPressed：既防重复提交，
              // 也让按钮呈现明确的不可用状态
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    )
                  : Text(_registerMode ? '注册并登录' : '登录'),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: _submitting ? null : _switchMode,
              child: Text(_registerMode ? '已有账号？去登录' : '还没有账号？去注册'),
            ),
          ),

          const SizedBox(height: 18),
          _PrivacyNote(),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            Icons.error_outline_rounded,
            size: 18,
            color: theme.colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 说明这里发生了什么、以及不登录也不影响什么。
///
/// 这一段不是装饰：安知是安全科普应用，
/// 必须让用户确信**不登录也能查安全知识、也能问 AI** ——
/// 否则他会以为要先注册，从而在紧急时刻被自己劝退。
class _PrivacyNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: kSurfaceColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            Icons.shield_outlined,
            size: 17,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              '不登录也能查看安全知识和使用 AI 问答。'
              '账号只用于保存收藏与浏览历史，密码经加密后存储，'
              '不会明文保存。',
              style: theme.textTheme.bodySmall?.copyWith(
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
