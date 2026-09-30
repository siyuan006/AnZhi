import '../core/app_constants.dart';

/// 安知 —— 知识卡片数据模型
///
/// 字段与 `docs/DATABASE.md` 中 `knowledge` 表严格对应。
/// 修改本模型时必须同步检查：
///   - backend/app/models/      数据库模型
///   - backend/app/schemas/     接口结构
///   - docs/DATABASE.md         数据库文档
class KnowledgeItem {
  const KnowledgeItem({
    required this.id,
    required this.title,
    required this.categoryId,
    required this.summary,
    this.content = '',
    this.riskLevel = RiskLevel.low,
    this.imageUrl,
    this.source,
    this.author,
    this.viewCount = 0,
    this.isFavorited = false,
    this.createdAt,
  });

  final int id;
  final String title;

  /// 对应 `categories.id`
  final int categoryId;
  final String summary;

  /// 正文。列表接口不返回该字段，详情接口才返回
  final String content;

  final RiskLevel riskLevel;
  final String? imageUrl;
  final String? source;
  final String? author;
  final int viewCount;

  /// 当前登录用户是否收藏了这一条。
  ///
  /// 由详情接口随身份返回；**未登录时恒为 `false`** ——
  /// 「没收藏」和「不知道是谁」在这个字段上是同一个值，
  /// 因此界面不能只看它来决定要不要显示收藏按钮，
  /// 还要看当前有没有登录。
  final bool isFavorited;

  final DateTime? createdAt;

  /// 所属分类，找不到时返回 `null`
  SafetyCategory? get category => categoryById(categoryId);

  /// 分类显示名，找不到分类时降级为「未分类」
  String get categoryName => category?.name ?? '未分类';

  /// 复制一份并覆盖部分字段。
  ///
  /// 两个用途：详情页拿到正文后异步取回最新浏览量；点收藏按钮后
  /// 在不重新请求整条内容的前提下更新收藏状态。
  KnowledgeItem copyWith({int? viewCount, bool? isFavorited}) {
    return KnowledgeItem(
      id: id,
      title: title,
      categoryId: categoryId,
      summary: summary,
      content: content,
      riskLevel: riskLevel,
      imageUrl: imageUrl,
      source: source,
      author: author,
      viewCount: viewCount ?? this.viewCount,
      isFavorited: isFavorited ?? this.isFavorited,
      createdAt: createdAt,
    );
  }

  /// 从后端 JSON 构造。
  ///
  /// 对缺失字段做了容错，避免后端字段调整导致客户端崩溃。
  factory KnowledgeItem.fromJson(Map<String, dynamic> json) {
    return KnowledgeItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: json['title'] as String? ?? '',
      categoryId: (json['category_id'] as num?)?.toInt() ?? 0,
      summary: json['summary'] as String? ?? '',
      content: json['content'] as String? ?? '',
      riskLevel: RiskLevel.fromValue(json['risk_level'] as String?),
      imageUrl: json['image_url'] as String?,
      source: json['source'] as String?,
      author: json['author'] as String?,
      viewCount: (json['view_count'] as num?)?.toInt() ?? 0,
      isFavorited: json['is_favorited'] as bool? ?? false,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'category_id': categoryId,
        'summary': summary,
        'content': content,
        'risk_level': riskLevel.value,
        'image_url': imageUrl,
        'source': source,
        'author': author,
        'view_count': viewCount,
        'is_favorited': isFavorited,
        'created_at': createdAt?.toIso8601String(),
      };
}
