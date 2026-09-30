import '../models/knowledge_item.dart';
import '../models/paged_result.dart';
import 'api_client.dart';

/// 安知 —— 知识系统接口
///
/// 对应 `docs/API.md` 第 4 节：
///   - `GET /api/knowledge`          知识列表
///   - `GET /api/knowledge/{id}`     知识详情
///   - `GET /api/categories`         六大分类
///
/// 注意：后端只返回**已审核发布**的内容（PROJECT_SPEC 第十五节）。
/// 因此在人工审核完成前，这个接口如实返回空列表 —— 这不是 bug，
/// 客户端必须能正确显示「暂无内容」而不是假装有数据。
class KnowledgeApi {
  KnowledgeApi({ApiClient? client}) : _client = client ?? ApiClient();

  final ApiClient _client;

  /// 拉取知识列表。
  ///
  /// 筛选与分页全部由服务端完成 —— 客户端不再本地过滤，
  /// 否则「第 1 页 20 条」里筛出来的结果数会和 `total` 对不上。
  ///
  /// [categoryId] 为空表示全部分类；[keyword] 为空表示不搜索。
  ///
  /// [preferCategoryIds] 是**排序偏好而不是筛选**：传了它，这些分类的
  /// 内容排在前面，其余的照常返回，`total` 也不变。关注一个领域
  /// 不该让用户看不到别的领域（`docs/API.md` 第 4 节）。
  /// 传空列表与不传等价。
  Future<PagedResult<KnowledgeItem>> fetchKnowledge({
    int? categoryId,
    String? keyword,
    String? riskLevel,
    List<int>? preferCategoryIds,
    int page = 1,
    int pageSize = 20,
  }) async {
    final Object? json = await _client.getJson(
      '/api/knowledge',
      query: <String, dynamic>{
        'category_id': categoryId,
        'keyword': keyword,
        'risk_level': riskLevel,
        'prefer_categories': preferCategoryIds,
        'page': page,
        'page_size': pageSize,
      },
    );

    if (json is! Map<String, dynamic>) {
      throw const ApiException('知识列表返回格式不正确');
    }
    return PagedResult<KnowledgeItem>.fromJson(json, KnowledgeItem.fromJson);
  }

  /// 拉取知识详情。
  ///
  /// 内容未发布或不存在时后端返回 404，这里会抛出
  /// [ApiException]，页面据此提示「内容不存在或已下架」。
  Future<KnowledgeItem> fetchKnowledgeDetail(int id) async {
    final Object? json = await _client.getJson('/api/knowledge/$id');

    if (json is! Map<String, dynamic>) {
      throw const ApiException('知识详情返回格式不正确');
    }
    return KnowledgeItem.fromJson(json);
  }

  /// 记录一次浏览，返回最新的浏览量。
  ///
  /// 与 [fetchKnowledgeDetail] 分开是刻意的：读详情是幂等的，
  /// 计数是一次写操作。若把计数塞进详情接口，浏览器预取、
  /// 失败重试、爬虫都会各算一次浏览。
  ///
  /// **失败不抛异常。** 浏览量是锦上添花的数据，
  /// 让「计数失败」把一次正常的阅读变成错误页是本末倒置 ——
  /// 调用方拿到 null 表示这次没记上，忽略即可。
  Future<int?> recordView(int id) async {
    try {
      final Object? json = await _client.postJson(
        '/api/knowledge/$id/view',
        const <String, dynamic>{},
      );
      if (json is! Map<String, dynamic>) return null;
      return (json['view_count'] as num?)?.toInt();
    } on ApiException {
      return null;
    }
  }

  void dispose() => _client.close();
}
