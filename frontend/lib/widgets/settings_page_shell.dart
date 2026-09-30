import 'package:flutter/material.dart';

import '../core/app_constants.dart';
import '../core/auth_controller.dart';
import '../models/user_settings.dart';
import '../services/api_client.dart';
import '../services/settings_api.dart';
import '../pages/login_page.dart';
import 'async_status.dart';

/// 安知 —— 设置页共用的状态机
///
/// 「关注领域」「首页布局」「通知设置」三页要做的事几乎一模一样：
///
///   取接口 → 未登录就如实说明 → 加载中转圈 → 出错可重试 →
///   改一项就 PUT 一次 → 按服务端返回的整份设置重画
///
/// 三份复制粘贴的话，「保存中不许再点」「失败不改变开关状态」
/// 这类细节迟早会在某一页漏掉一处。这里收成一份，各页只负责画内容。
///
/// 三页都得是 `StatefulWidget`，因此用 mixin 而不是包一层基类。
mixin SettingsPageShell<T extends StatefulWidget> on State<T> {
  /// 子类把测试注入的接口交出来；生产路径返回 `null`，
  /// 由本 mixin 从 `AuthScope` 上取那个**已经接好鉴权头**的实例。
  ///
  /// 不能在这里自己 `SettingsApi()` —— 那是个匿名客户端，
  /// 两个接口都会拿到 401，而现象看起来完全像是后端的毛病。
  SettingsApi? get injectedSettingsApi;

  SettingsApi? _api;
  bool _started = false;

  bool loading = true;
  String? error;
  UserSettings? settings;

  /// 正在保存的项，用来把那一行置灰并显示转圈。
  /// 键由各页自己定（分类用 `category-3`、模块用 `module-ai`）。
  final Set<String> saving = <String>{};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;

    // 在 didChangeDependencies 里取而不是 initState：
    // `AuthScope.maybeOf` 要读 InheritedWidget，在 initState 里读会被框架断言拦下。
    _api = injectedSettingsApi ?? AuthScope.maybeOf(context)?.settingsApi;
    load();
  }

  bool get isLoggedIn => AuthScope.maybeOf(context)?.isLoggedIn ?? false;

  Future<void> load({bool showLoading = true}) async {
    final SettingsApi? api = _api;
    if (api == null) {
      if (mounted) setState(() => loading = false);
      return;
    }

    if (showLoading && mounted) {
      setState(() {
        loading = true;
        error = null;
      });
    }

    try {
      final UserSettings result = await api.fetch();
      if (!mounted) return;
      setState(() {
        loading = false;
        error = null;
        settings = result;
      });
    } on ApiException catch (failure) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = failure.message;
      });
    }
  }

  /// 保存一项。[key] 只用于标记哪一行在转圈，不参与请求。
  ///
  /// 三个参数都是「这次要不要改这一项」，`null` 表示不改 ——
  /// 请求体里不会出现这个键（后端的语义见 `docs/API.md` 第 8 节）。
  ///
  /// **失败时不改本地状态。** 开关停在原处，并弹一句说明。
  /// 本地先翻过去、失败再翻回来，用户会看到开关自己跳两下，
  /// 比「点了没动，然后告诉你为什么」更难理解。
  Future<void> save(
    String key, {
    List<int>? followedCategories,
    List<String>? homeModules,
    bool? notifyEnabled,
  }) async {
    final SettingsApi? api = _api;
    if (api == null || saving.contains(key)) return;

    setState(() => saving.add(key));

    try {
      final UserSettings result = await api.update(
        followedCategories: followedCategories,
        homeModules: homeModules,
        notifyEnabled: notifyEnabled,
      );
      if (!mounted) return;
      setState(() {
        saving.remove(key);
        settings = result;
      });
    } on ApiException catch (failure) {
      if (!mounted) return;
      setState(() => saving.remove(key));
      toast(failure.message);
    }
  }

  void toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
  }

  Future<void> openLogin() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const LoginPage()),
    );
    if (!mounted) return;
    await load();
  }

  /// 未登录 / 加载中 / 出错三种形态都在这里处理，都不是才轮到子类画内容。
  ///
  /// 「未登录」借的是 `EmptyPlaceholder` 而不是自己拼一段文字：
  /// 三页的措辞、图标、返回路径要长得一样，用户才认得出是同一件事。
  Widget buildSettingsShell({
    required String loadingMessage,
    required String loginMessage,
    required Widget Function(UserSettings settings) builder,
  }) {
    if (!isLoggedIn) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(kPagePadding),
        child: Column(
          children: <Widget>[
            EmptyPlaceholder(
              icon: Icons.tune_rounded,
              title: '请先登录',
              message: loginMessage,
            ),
            OutlinedButton(onPressed: openLogin, child: const Text('去登录')),
          ],
        ),
      );
    }

    if (loading) return LoadingPlaceholder(message: loadingMessage);

    if (error != null) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(kPagePadding, 8, kPagePadding, 24),
        child: ErrorPlaceholder(
          message: error!,
          hint: '设置保存在后端，请确认后端已启动',
          onRetry: load,
        ),
      );
    }

    final UserSettings? current = settings;
    if (current == null) {
      // 走到这里说明 `fetch` 成功了却没填上 settings —— 不该发生。
      // 兜底成加载态，总好过子类拿着 null 崩掉。
      return LoadingPlaceholder(message: loadingMessage);
    }

    return builder(current);
  }
}
