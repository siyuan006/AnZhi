import '../core/relative_time.dart';
import 'knowledge_item.dart';

/// 安知 —— 浏览历史数据模型
///
/// 对应 `docs/API.md` 第 6 节 `GET /api/history` 的 `items` 元素。
///
/// 与 `FavoriteItem` 一样是**嵌套结构**：历史记录本身（id / viewed_at）
/// 外面套一份知识摘要，一次请求就能把每行要显示的标题、分类、
/// 风险等级全拿到。
///
/// 与收藏的唯一区别是时间字段：收藏看的是「什么时候收的」，
/// 历史看的是「什么时候看的」，而且**同一篇的 `viewed_at` 会
/// 随着每次浏览往后推** —— 后端保证同一篇只留一条记录。
class HistoryItem {
  const HistoryItem({
    required this.id,
    required this.knowledgeId,
    required this.knowledge,
    this.viewedAt,
  });

  /// **历史记录**的 id，不是知识的 id。
  /// 删除单条历史用的是 [knowledgeId] —— 历史按知识去重。
  final int id;

  final int knowledgeId;

  /// 浏览过的知识。
  ///
  /// 后端只返回**仍可见**（已发布）的知识，所以正常情况下这里的
  /// [KnowledgeItem.title] 一定非空。字段缺失时的兜底见 [fromJson]。
  final KnowledgeItem knowledge;

  /// 最近一次浏览的时间。
  final DateTime? viewedAt;

  /// 标题为空说明后端给的嵌套对象是空的 —— 界面据此显示
  /// 「内容已下架」，而不是渲染一行空白让人以为界面坏了。
  bool get isBroken => knowledge.title.isEmpty;

  factory HistoryItem.fromJson(Map<String, dynamic> json) {
    final int knowledgeId = (json['knowledge_id'] as num?)?.toInt() ?? 0;
    final Object? nested = json['knowledge'];

    return HistoryItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      knowledgeId: knowledgeId,
      viewedAt: parseServerTime(json['viewed_at'] as String?),
      // 兜底而不是抛异常：一条解析不了的数据不该让整个历史页打不开。
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
