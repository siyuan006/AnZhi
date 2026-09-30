import '../models/user_settings.dart';
import 'api_client.dart';

/// 安知 —— 个性化设置接口
///
/// 对应 `docs/API.md` 第 8 节。两个接口**都要求登录**：
/// 设置是跟着账号走的，用匿名客户端去调只会拿到 401，
/// 而现象看起来完全像是后端的毛病。因此生产路径上必须传入
/// `AuthController.apiClient`（或直接用 `AuthController.settingsApi`）。
class SettingsApi {
  SettingsApi({ApiClient? client})
      : _client = client ?? ApiClient(),
        _ownsClient = client == null;

  final ApiClient _client;

  final bool _ownsClient;

  /// 读当前设置。
  ///
  /// **从没设置过的用户拿到的是默认值，不是 404** —— 后端保证的。
  /// 所以调用方不需要处理「还没有设置」这种状态。
  Future<UserSettings> fetch() async {
    final Object? json = await _client.getJson('/api/settings');

    if (json is! Map<String, dynamic>) {
      throw const ApiException('设置返回格式不正确');
    }
    return UserSettings.fromJson(json);
  }

  /// 更新设置，返回**完整的最新设置**。
  ///
  /// 三个参数都是「这次要不要改这一项」，为 `null` 表示不改 ——
  /// 请求体里根本不会出现这个键。这与后端的语义一致：
  ///
  ///     只改通知开关  →  update(notifyEnabled: false)
  ///     取消全部关注  →  update(followedCategories: <int>[])
  ///
  /// 传空列表与不传**必须区分得开**：两者混为一谈的话，
  /// 用户永远取消不掉最后一个关注分类。
  ///
  /// 返回的是服务端算好的整份设置，不是本地拼出来的 ——
  /// 服务端会去重、排序，客户端自己算的话显示的东西和存下来的会对不上。
  Future<UserSettings> update({
    List<int>? followedCategories,
    List<String>? homeModules,
    bool? notifyEnabled,
  }) async {
    final Map<String, dynamic> body = <String, dynamic>{
      'followed_categories': ?followedCategories,
      'home_modules': ?homeModules,
      'notify_enabled': ?notifyEnabled,
    };

    final Object? json = await _client.putJson('/api/settings', body);

    if (json is! Map<String, dynamic>) {
      throw const ApiException('设置返回格式不正确');
    }
    return UserSettings.fromJson(json);
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }
}
