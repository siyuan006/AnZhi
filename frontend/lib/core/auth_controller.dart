import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import '../models/auth_user.dart';
import '../services/api_client.dart';
import '../services/auth_api.dart';
import '../services/auth_store.dart';
import '../services/favorite_api.dart';
import '../services/history_api.dart';
import '../services/settings_api.dart';

/// 安知 —— 登录状态
///
/// 全应用只有一份，负责三件事：
///   1. 持有当前 token（[ApiClient] 通过回调每次现取，见 `api_client.dart`）
///   2. 持有当前用户，供界面显示登录 / 未登录两种形态
///   3. 把「登录状态变了」广播出去
///
/// ⚠️ **本类不保存密码。** 口令只在登录页面的局部变量里存在一瞬间，
/// 提交完就丢。这里存的是 token —— 它只代表「已登录」，
/// 泄露的后果是有限的、可撤销的（改 JWT_SECRET 即可全部作废）。
class AuthController extends ChangeNotifier {
  /// 注入点是底层的 [http.Client]，**不是 [AuthApi]**。
  ///
  /// 这一点很要紧：AuthApi 必须用「能读到本对象 token」的客户端，
  /// 否则 `/api/auth/me` 不会带上 Authorization 头，
  /// 恢复登录态时会永远拿到 401 —— 表现是「每次打开 App 都要重新登录」，
  /// 而且看起来完全像是后端的毛病。
  /// 把 token 的接线交给本类自己，就不会有人接错。
  AuthController({
    http.Client? httpClient,
    String? baseUrl,
    AuthStore? store,
  }) : _store = store ?? MemoryAuthStore() {
    // 在这里而不是初始化列表里构造：token 回调要读 `_token`，
    // 而初始化列表阶段还访问不到 this。
    _client = ApiClient(
      httpClient: httpClient,
      baseUrl: baseUrl,
      token: () => _token,
    );
    _api = AuthApi(client: _client);
  }

  final AuthStore _store;
  late final ApiClient _client;
  late final AuthApi _api;

  /// 收藏接口，已经接好鉴权头。
  ///
  /// 由本类统一持有，**页面不要自己造一个** —— 见下面 [apiClient] 的说明。
  /// 收藏是「这份数据属于谁」的接口，用匿名客户端去调只会拿到 401。
  late final FavoriteApi favoriteApi = FavoriteApi(client: _client);

  /// 浏览历史接口，已经接好鉴权头。同样是「这份数据属于谁」的接口。
  ///
  /// 注意这里只有**读和删** —— 记录浏览是详情页调 `/view` 时后端顺带
  /// 完成的，见 `history_api.dart` 的说明。
  late final HistoryApi historyApi = HistoryApi(client: _client);

  /// 个性化设置接口，已经接好鉴权头。同样是「这份数据属于谁」的接口。
  ///
  /// ⚠️ **没有「未登录也能读」这条路**：后端两个接口都要登录。
  /// 因此设置页必须自己处理未登录 —— 见 `pages/settings_follow_page.dart`。
  late final SettingsApi settingsApi = SettingsApi(client: _client);

  /// 已接好鉴权头的底层客户端，供其它需要登录态的接口复用。
  ///
  /// 收藏、浏览历史这类接口都以「当前是谁」为前提，各自新建一个匿名
  /// 客户端只会拿到 401 —— 而且看起来完全像是后端的毛病。
  ///
  /// ⚠️ **借用方不要 `close()` 它。** 它归本对象所有，[dispose] 时统一关闭。
  /// 共用一个 client 时，任何一方 close 都会让另一方莫名其妙地
  /// 「连不上服务器」——`test/integration/live_backend_test.dart` 里
  /// 特意为每个接口单独建 client，就是为了躲开这个坑。
  ApiClient get apiClient => _client;

  AuthUser? _user;
  String? _token;
  bool _restoring = true;

  /// 当前登录用户；未登录为 `null`。
  AuthUser? get user => _user;

  bool get isLoggedIn => _user != null;

  /// 启动时是否还在确认本地凭证。
  ///
  /// 界面据此区分「还没登录」和「还在确认」——
  /// 不区分的话，已登录用户每次打开 App 都会看到一瞬间的「未登录」。
  bool get restoring => _restoring;

  /// 供 [ApiClient] 读取的 token。**未登录时返回 null**，
  /// 请求就不会带上 Authorization 头。
  String? get token => _token;

  /// 启动时调用一次：如果本地存着 token，验证它还有没有效。
  ///
  /// 验证失败**静默登出**，不弹错误 —— 用户什么都没做，
  /// 却看到一句「登录已过期」只会让他困惑。下次操作时会重新要求登录。
  Future<void> restore() async {
    final String? saved = await _store.readToken();
    if (saved == null || saved.isEmpty) {
      _restoring = false;
      notifyListeners();
      return;
    }

    _token = saved;
    try {
      _user = await _api.me();
    } on ApiException {
      await _clearSession();
    }
    _restoring = false;
    notifyListeners();
  }

  /// 登录。成功返回 `null`，失败返回一句可直接展示的中文。
  ///
  /// 用返回值而不是抛异常表达「用户名或密码不正确」：
  /// 调用方只需处理一种失败形态，不容易漏掉分支。
  Future<String?> login({
    required String username,
    required String password,
  }) async {
    return _run(() => _api.login(username: username, password: password));
  }

  Future<String?> register({
    required String username,
    required String password,
    String? nickname,
  }) async {
    return _run(
      () => _api.register(
        username: username,
        password: password,
        nickname: nickname,
      ),
    );
  }

  Future<String?> _run(Future<AuthSession> Function() action) async {
    try {
      final AuthSession session = await action();
      await _store.writeToken(session.token);
      _token = session.token;
      _user = session.user;
      notifyListeners();
      return null;
    } on ApiException catch (error) {
      return error.message;
    }
  }

  /// 登出。
  ///
  /// **只清本地。** 不做「通知服务端作废 token」这一步：
  /// JWT 是无状态的，服务端没有可作废的会话记录，
  /// 伪造一个「已作废」的接口只会让人以为 token 被撤销了，实际没有。
  /// 真正需要立刻让所有 token 失效时，换掉 JWT_SECRET 即可。
  Future<void> logout() async {
    await _clearSession();
    notifyListeners();
  }

  Future<void> _clearSession() async {
    await _store.clear();
    _token = null;
    _user = null;
  }

  @override
  void dispose() {
    _api.dispose();
    super.dispose();
  }
}

/// 把 [AuthController] 提供给整棵子树。
///
/// 用 [InheritedNotifier] 而不是层层传参：收藏按钮在知识详情页、
/// 登录状态在「我的」页、历史记录在另一个页面，
/// 一路透传会把中间那些完全用不到它的组件也污染一遍。
///
/// 也不引入 provider 之类的状态管理库 —— 一个 [InheritedNotifier]
/// 就够了，没必要为这点需求新增依赖。
class AuthScope extends InheritedNotifier<AuthController> {
  const AuthScope({
    super.key,
    required AuthController controller,
    required super.child,
  }) : super(notifier: controller);

  /// 取当前的登录状态。外层没有 [AuthScope] 时返回 `null`，
  /// 便于单独 pump 某个页面做测试（此时按未登录处理）。
  static AuthController? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<AuthScope>()
        ?.notifier;
  }
}
