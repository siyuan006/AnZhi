import '../models/auth_user.dart';
import 'api_client.dart';

/// 安知 —— 认证接口
///
/// 对应后端 `/api/auth/*`（docs/API.md 第 11 节）。
///
/// 本层只做「发请求 + 解析」，失败一律抛 [ApiException]，
/// 消息可直接展示给用户 —— 校验规则由后端说了算，
/// 客户端不自己再判一遍（两处规则迟早会不一致，
/// 而用户看到的是两份互相矛盾的提示）。
class AuthApi {
  AuthApi({ApiClient? client}) : _client = client ?? ApiClient();

  final ApiClient _client;

  /// 注册并直接拿到 token。
  Future<AuthSession> register({
    required String username,
    required String password,
    String? nickname,
  }) async {
    final Object? json = await _client.postJson('/api/auth/register', <String, dynamic>{
      'username': username,
      'password': password,
      if (nickname != null && nickname.isNotEmpty) 'nickname': nickname,
    });
    return AuthSession.fromJson(json! as Map<String, dynamic>);
  }

  /// 登录。
  Future<AuthSession> login({
    required String username,
    required String password,
  }) async {
    final Object? json = await _client.postJson('/api/auth/login', <String, dynamic>{
      'username': username,
      'password': password,
    });
    return AuthSession.fromJson(json! as Map<String, dynamic>);
  }

  /// 用本地 token 换取当前用户，用来判断「这枚 token 还有效吗」。
  ///
  /// 客户端自己解析 `exp` 只能知道「有没有过期」，
  /// 挡不住「用户已被删除」——只有问一次服务端才知道。
  Future<AuthUser> me() async {
    final Object? json = await _client.getJson('/api/auth/me');
    return AuthUser.fromJson(json! as Map<String, dynamic>);
  }

  void dispose() => _client.close();
}

/// 一次成功的登录 / 注册结果：token + 用户。
class AuthSession {
  const AuthSession({required this.token, required this.user});

  final String token;
  final AuthUser user;

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    return AuthSession(
      token: json['access_token'] as String,
      user: AuthUser.fromJson(json['user'] as Map<String, dynamic>),
    );
  }
}
