import '../models/comment_item.dart';
import '../models/like_state.dart';
import '../models/paged_result.dart';
import '../models/post_item.dart';
import 'api_client.dart';

/// 安知 —— 社区接口
///
/// 对应 `docs/API.md` 第 7 节。
///
/// 读（列表、详情、评论列表）不需要登录，写（发表评论、点赞）需要。
/// 两件事共用一个客户端：未登录时 `AuthController` 的 token 回调返回
/// `null`，请求就不带 Authorization 头，读照样能用；登录之后写才成立。
/// 因此**生产路径上必须传入 `AuthController.apiClient`** ——
/// 传一个匿名客户端的话，读没问题，写会拿到 401，
/// 而现象看起来完全像是后端的毛病。
///
/// 读了 token 的接口（列表、详情、我的帖子）会多返回一个 `is_liked`：
/// 它答的是「我点过吗」。匿名请求恒为 `false`。
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

  /// 我发过的帖子。需要登录，未登录时服务端返回 401「请先登录」。
  ///
  /// 已删除的帖子不在这里出现 —— 删除是软删除，但「删了」
  /// 对作者自己同样意味着不可见。
  Future<PagedResult<PostItem>> fetchMyPosts({
    int page = 1,
    int pageSize = 20,
  }) async {
    final Object? json = await _client.getJson(
      '/api/posts/mine',
      query: <String, dynamic>{'page': page, 'page_size': pageSize},
    );

    if (json is! Map<String, dynamic>) {
      throw const ApiException('我的帖子返回格式不正确');
    }
    return PagedResult<PostItem>.fromJson(json, PostItem.fromJson);
  }

  /// 发布帖子。需要登录。
  ///
  /// 返回的是**详情结构**（含正文）：发完立刻跳进详情页是最自然的
  /// 动作，少一次请求。
  Future<PostItem> createPost({
    required String title,
    required String content,
    int? categoryId,
  }) async {
    final Object? json = await _client.postJson('/api/posts', <String, dynamic>{
      'title': title,
      'content': content,
      // 不选分类时就传 null。注意 ApiClient 只清理**查询参数**里的
      // null，请求体是原样发出去的；服务端把 null 当作
      // 「不属于任何分类」，与数据库里 category_id 可空一致。
      'category_id': categoryId,
    });

    if (json is! Map<String, dynamic>) {
      throw const ApiException('发布帖子返回格式不正确');
    }
    return PostItem.fromJson(json);
  }

  /// 删除自己的帖子。需要登录；删别人的会拿到 403「只能删除自己的帖子」。
  ///
  /// 服务端是软删除，返回 204 无响应体。
  Future<void> deletePost(int postId) async {
    await _client.deleteJson('/api/posts/$postId');
  }

  /// 点赞。需要登录，未登录时服务端返回 401「请先登录」。
  ///
  /// **幂等**：重复点赞不报错，也不会多出一个赞，返回的仍是当前状态。
  Future<LikeState> like(int postId) async {
    final Object? json = await _client.postJson(
      '/api/posts/$postId/like',
      const <String, dynamic>{},
    );

    return _likeState(json, '点赞');
  }

  /// 取消点赞。同样幂等：本来就没点过也算成功。
  ///
  /// 与收藏、历史的 `DELETE` 不同，这里**有响应体** ——
  /// 爱心旁边的数字要以服务端算的为准（见 [LikeState]）。
  Future<LikeState> unlike(int postId) async {
    final Object? json = await _client.deleteJson('/api/posts/$postId/like');

    return _likeState(json, '取消点赞');
  }

  LikeState _likeState(Object? json, String action) {
    if (json is! Map<String, dynamic>) {
      throw ApiException('$action返回格式不正确');
    }
    return LikeState.fromJson(json);
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }
}
