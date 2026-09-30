/// 安知 —— 登录凭证的存放位置
///
/// 抽成接口是为了把「token 存在哪」和「谁在用 token」分开：
/// 目前只有内存实现，将来换成磁盘持久化时，
/// 调用方（[AuthController]）一行都不用改。
///
/// ⚠️ **当前实现不持久化**：App 关掉后 token 就没了，需要重新登录。
/// 要做到「下次打开还是登录状态」，需要一个存储插件
/// （`shared_preferences` 之类）来写入 App 私有目录。
/// 那属于新增第三方依赖，按 AI_RULES 第五节需要先说明并获得确认，
/// 因此**没有擅自引入** —— 这里如实标注，而不是假装已经持久化了。
library;

/// token 的读写接口。
abstract class AuthStore {
  Future<String?> readToken();

  Future<void> writeToken(String token);

  /// 清除 token。登出、以及「token 已失效」时都要调用。
  Future<void> clear();
}

/// 只存在内存里的实现。
///
/// 进程结束即消失。行为简单、可预测，测试里也不必清理磁盘。
class MemoryAuthStore implements AuthStore {
  String? _token;

  @override
  Future<String?> readToken() async => _token;

  @override
  Future<void> writeToken(String token) async => _token = token;

  @override
  Future<void> clear() async => _token = null;
}
