import '../models/favorite_item.dart';
import '../models/paged_result.dart';
import 'api_client.dart';

/// 安知 —— 收藏接口
///
/// 对应 `docs/API.md` 第 5 节：
///   - `GET    /api/favorites`                 我的收藏（分页）
///   - `POST   /api/favorites`                 收藏
///   - `DELETE /api/favorites/{knowledge_id}`  取消收藏
///
/// **三个接口都要求登录。** 未登录时后端返回 401 + 「请先登录」，
/// 本类不把它翻译成别的说法 —— 页面据此直接引导用户去登录页。
///
/// 收藏与取消都是**幂等**的：
///   - 收藏一条已收藏的知识 → 200，返回原来那条记录
///   - 取消一条没收藏过的知识 → 204，和真删掉一样
///
/// 因此客户端不需要在本地维护「我是不是已经收藏过了」这份状态，
/// 重复点击、失败重试、两个页面同时操作都不会弹出错误。
///
/// ⚠️ 本类的实例**由 `AuthController` 统一持有**（见 `auth_controller.dart`），
/// 页面应当从 `AuthScope` 取，不要自己 `new` —— 它需要一个带着
/// 当前 token 的客户端，而那个客户端的所有权在 `AuthController` 手上。
class FavoriteApi {
  FavoriteApi({ApiClient? client}) : _client = client ?? ApiClient();

  final ApiClient _client;

  /// 拉取当前用户的收藏，按收藏时间倒序。
  ///
  /// 只返回仍可见的知识：收藏之后内容被撤下审核时，列表里不会留下
  /// 一条点不开的入口（此时 `total` 会小于实际收藏数，这是刻意的）。
  Future<PagedResult<FavoriteItem>> fetchFavorites({
    int page = 1,
    int pageSize = 20,
  }) async {
    final Object? json = await _client.getJson(
      '/api/favorites',
      query: <String, dynamic>{'page': page, 'page_size': pageSize},
    );

    if (json is! Map<String, dynamic>) {
      throw const ApiException('收藏列表返回格式不正确');
    }
    return PagedResult<FavoriteItem>.fromJson(json, FavoriteItem.fromJson);
  }

  /// 收藏一条知识。已经收藏过同样视为成功。
  Future<void> add(int knowledgeId) async {
    await _client.postJson(
      '/api/favorites',
      <String, dynamic>{'knowledge_id': knowledgeId},
    );
  }

  /// 取消收藏。本来就没收藏过同样视为成功。
  Future<void> remove(int knowledgeId) async {
    await _client.deleteJson('/api/favorites/$knowledgeId');
  }

  void dispose() => _client.close();
}
