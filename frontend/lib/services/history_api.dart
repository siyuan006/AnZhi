import '../models/history_item.dart';
import '../models/paged_result.dart';
import 'api_client.dart';

/// 安知 —— 浏览历史接口
///
/// 对应 `docs/API.md` 第 6 节：
///   - `GET    /api/history`                 浏览历史（分页）
///   - `DELETE /api/history`                 清空全部
///   - `DELETE /api/history/{knowledge_id}`  删除单条
///
/// **三个接口都要求登录。** 未登录时后端返回 401 + 「请先登录」，
/// 本类不把它翻译成别的说法 —— 页面据此直接引导用户去登录页。
///
/// ⚠️ **这里没有「记录一次浏览」的方法，这是刻意的。**
/// 历史是在用户打开知识详情页时由后端**顺带**写下的：
/// 详情页本来就会调 `POST /api/knowledge/{id}/view` 记一次浏览量，
/// 那个接口带着可选登录身份，登录了就顺手更新历史。
/// 客户端不需要、也不应该再单独发一次「我看了这条」——
/// 那会在网络重试时产生重复写入，而且多一次往返。
///
/// 两个删除接口都是**幂等**的：
///   - 删一条本来就没有的历史 → 204，和真删掉一样
///   - 清空一个本来就空的历史 → 204
/// 因此客户端重复点击、失败重试都不会弹出错误。
///
/// ⚠️ 本类的实例**由 `AuthController` 统一持有**（见 `auth_controller.dart`），
/// 页面应当从 `AuthScope` 取，不要自己 `new` —— 它需要一个带着
/// 当前 token 的客户端，而那个客户端的所有权在 `AuthController` 手上。
class HistoryApi {
  HistoryApi({ApiClient? client}) : _client = client ?? ApiClient();

  final ApiClient _client;

  /// 拉取当前用户的浏览历史，按最近浏览倒序。
  ///
  /// 只返回仍可见的知识：浏览过、之后被撤回的内容不会留在列表里
  /// （此时 `total` 会小于数据库里的历史行数，这是刻意的）。
  Future<PagedResult<HistoryItem>> fetchHistory({
    int page = 1,
    int pageSize = 20,
  }) async {
    final Object? json = await _client.getJson(
      '/api/history',
      query: <String, dynamic>{'page': page, 'page_size': pageSize},
    );

    if (json is! Map<String, dynamic>) {
      throw const ApiException('浏览历史返回格式不正确');
    }
    return PagedResult<HistoryItem>.fromJson(json, HistoryItem.fromJson);
  }

  /// 删除单条历史。本来就没有同样视为成功。
  Future<void> remove(int knowledgeId) async {
    await _client.deleteJson('/api/history/$knowledgeId');
  }

  /// 清空全部历史。
  Future<void> clear() async {
    await _client.deleteJson('/api/history');
  }

  void dispose() => _client.close();
}
