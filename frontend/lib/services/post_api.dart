import '../models/paged_result.dart';
import '../models/post_item.dart';
import 'api_client.dart';

/// 安知 —— 社区接口
///
/// 对应 `docs/API.md` 第 7 节。阶段 12a 只有两个**读**接口：
///   - `GET /api/posts`        帖子列表
///   - `GET /api/posts/{id}`   帖子详情
///
/// 评论（12b）、点赞（12c）、发帖（12d）在后续补上。
///
/// **两个接口都不需要登录**，因此这里用的是匿名 `ApiClient` ——
/// 社区内容是公开的，浏览它没有理由要求身份（docs/API.md 第 11 节）。
/// 这与 `FavoriteApi` / `HistoryApi` 不同：那两个是「这份数据属于谁」
/// 的接口，必须带着 token。
class PostApi {
  PostApi({ApiClient? client}) : _client = client ?? ApiClient();

  final ApiClient _client;

  /// 拉取帖子列表。
  ///
  /// 筛选与分页全部由服务端完成 —— 客户端不再本地过滤，
  /// 否则「第 1 页 20 条」里筛出来的结果数会和 `total` 对不上。
  ///
  /// 返回的每一项只有 [PostItem.summary]，没有正文。
  Future<PagedResult<PostItem>> fetchPosts({
    int? categoryId,
    String? keyword,
    int page = 1,
    int pageSize = 20,
  }) async {
    final Object? json = await _client.getJson(
      '/api/posts',
      query: <String, dynamic>{
        'category_id': categoryId,
        'keyword': keyword,
        'page': page,
        'page_size': pageSize,
      },
    );

    if (json is! Map<String, dynamic>) {
      throw const ApiException('帖子列表返回格式不正确');
    }
    return PagedResult<PostItem>.fromJson(json, PostItem.fromJson);
  }

  /// 拉取帖子详情（含正文）。
  ///
  /// 帖子不存在或已隐藏时后端返回 404，这里会抛出 [ApiException]，
  /// 页面据此提示「帖子不存在或已删除」。
  Future<PostItem> fetchPostDetail(int id) async {
    final Object? json = await _client.getJson('/api/posts/$id');

    if (json is! Map<String, dynamic>) {
      throw const ApiException('帖子详情返回格式不正确');
    }
    return PostItem.fromJson(json);
  }

  void dispose() => _client.close();
}
