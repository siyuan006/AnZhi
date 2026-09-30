/// 安知 —— 分页响应模型
///
/// 对应 `docs/API.md` 1.3 节与后端 `app/schemas/common.py` 中的 `Page[T]`：
///
/// ```json
/// { "total": 128, "page": 1, "page_size": 20, "items": [] }
/// ```
///
/// 用泛型实现，收藏列表、历史记录、帖子列表都可以复用同一套结构。
class PagedResult<T> {
  const PagedResult({
    required this.total,
    required this.page,
    required this.pageSize,
    required this.items,
  });

  /// 符合条件的总条数（不是当前页条数）
  final int total;
  final int page;
  final int pageSize;
  final List<T> items;

  /// 是否还有下一页。
  ///
  /// 用「已加载条数 < 总数」判断，而不是「当前页是否满页」——
  /// 后者在总数恰好是页大小整数倍时会多请求一次空页。
  bool get hasMore => page * pageSize < total;

  /// 从后端 JSON 构造，[itemFromJson] 负责把单个元素转成 `T`。
  ///
  /// 后端字段缺失或类型不符时降级为安全的默认值，
  /// 避免后端调整字段导致整页崩溃。
  factory PagedResult.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) itemFromJson,
  ) {
    final Object? rawItems = json['items'];
    return PagedResult<T>(
      total: (json['total'] as num?)?.toInt() ?? 0,
      page: (json['page'] as num?)?.toInt() ?? 1,
      pageSize: (json['page_size'] as num?)?.toInt() ?? 20,
      items: rawItems is List
          ? rawItems
              .whereType<Map<String, dynamic>>()
              .map(itemFromJson)
              .toList(growable: false)
          : const <Never>[],
    );
  }

  /// 空结果，用于「加载失败后仍需渲染列表」等场景
  static PagedResult<T> empty<T>({int page = 1, int pageSize = 20}) =>
      PagedResult<T>(total: 0, page: page, pageSize: pageSize, items: <T>[]);
}
