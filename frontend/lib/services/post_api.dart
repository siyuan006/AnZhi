import '../models/comment_item.dart';
import '../models/paged_result.dart';
import '../models/post_item.dart';
import 'api_client.dart';

/// 安知 —— 社区接口
///
/// 对应 `docs/API.md` 第 7 节。
///
/// 读（列表、详情、评论列表）不需要登录，写（发表评论）需要。
/// 两件事共用一个客户端：未登录时 `AuthController` 的 token 回调返回
/// `null`，请求就不带 Authorization 头，读照样能用；登录之后写才成立。
/// 因此**生产路径上必须传入 `AuthController.apiClient`** ——
/// 传一个匿名客户端的话，读没问题，发评论会拿到 401，
/// 而现象看起来完全像是后端的毛病。
///
/// 点赞（12c）、发帖（12d）在后续补上。
class PostApi {
  PostApi({ApiClient? client})
      : _client = client ?? ApiClient(),
        _ownsClient = client == null;

  final ApiClient _client;

  final bool _ownsClient;

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

  /// 拉取某条帖子的评论，按时间正序 —— 与帖子列表相反。
  Future<PagedResult<CommentItem>> fetchComments(
    int postId, {
    int page = 1,
    int pageSize = 20,
  }) async {
    final Object? json = await _client.getJson(
      '/api/posts/$postId/comments',
      query: <String, dynamic>{'page': page, 'page_size': pageSize},
    );

    if (json is! Map<String, dynamic>) {
      throw const ApiException('评论列表返回格式不正确');
    }
    return PagedResult<CommentItem>.fromJson(json, CommentItem.fromJson);
  }

  /// 发表评论。需要登录，未登录时服务端返回 401「请先登录」。
  Future<CommentItem> postComment(int postId, String content) async {
    final Object? json = await _client.postJson(
      '/api/posts/$postId/comments',
      <String, dynamic>{'content': content},
    );

    if (json is! Map<String, dynamic>) {
      throw const ApiException('发表评论返回格式不正确');
    }
    return CommentItem.fromJson(json);
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }
}
