import 'knowledge_item.dart';

/// 安知 —— 收藏记录数据模型
///
/// 对应 `docs/API.md` 第 5 节 `GET /api/favorites` 的 `items` 元素。
///
/// 后端返回的是一个**嵌套结构**：收藏记录本身（id / created_at）
/// 外面套一份知识摘要。这样收藏列表一次请求就能把每行要显示的标题、
/// 分类、风险等级全拿到，不需要对每一行再发一次详情请求（N+1）。
class FavoriteItem {
  const FavoriteItem({
    required this.id,
    required this.knowledgeId,
    required this.knowledge,
    this.createdAt,
  });

  /// **收藏记录**的 id，不是知识的 id。
  /// 取消收藏用的是 [knowledgeId] —— 收藏是按知识去重的。
  final int id;

  final int knowledgeId;

  /// 被收藏的知识。
  ///
  /// 后端只返回**仍可见**（已发布）的知识，所以正常情况下这里的
  /// [KnowledgeItem.title] 一定非空。字段缺失时的兜底见 [fromJson]。
  final KnowledgeItem knowledge;

  final DateTime? createdAt;

  /// 标题为空说明后端给的嵌套对象是空的 —— 界面据此显示
  /// 「内容已下架」，而不是渲染一行空白让人以为界面坏了。
  bool get isBroken => knowledge.title.isEmpty;

  factory FavoriteItem.fromJson(Map<String, dynamic> json) {
    final int knowledgeId = (json['knowledge_id'] as num?)?.toInt() ?? 0;
    final Object? nested = json['knowledge'];

    return FavoriteItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      knowledgeId: knowledgeId,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
      // 兜底而不是抛异常：一条解析不了的数据不该让整个收藏页打不开。
      knowledge: nested is Map<String, dynamic>
          ? KnowledgeItem.fromJson(nested)
          : KnowledgeItem(
              id: knowledgeId,
              title: '',
              categoryId: 0,
              summary: '',
            ),
    );
  }
}
