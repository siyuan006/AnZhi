import '../core/app_constants.dart';
import '../core/relative_time.dart';

/// 安知 —— 社区帖子数据模型
///
/// 字段与 `backend/app/schemas/post.py` 严格对应。
/// 修改本模型时必须同步检查：
///   - backend/app/models/post.py     数据库模型
///   - backend/app/schemas/post.py    接口结构
///   - docs/DATABASE.md 3.6           数据库文档
///
/// **刻意不包含作者的 `username`。** 对社区来说只需要一个署名，
/// 而用户名是登录凭据的一半，后端也不会返回它。
class PostAuthor {
  const PostAuthor({required this.id, required this.name});

  final int id;

  /// 署名：昵称优先，没设昵称时是用户名
  final String name;

  /// 头像里显示的那个字。
  ///
  /// 用 `runes` 取而不是 `name[0]`：后者按 UTF-16 码元切，
  /// 遇到 emoji 这类补充平面字符会切出半个代理对，渲染成乱码方块。
  /// （没有用 `characters` 包 —— 那不是本项目的直接依赖，
  /// 为一个首字母去动 pubspec 不划算。）
  String get initial =>
      name.isEmpty ? '?' : String.fromCharCode(name.runes.first);

  factory PostAuthor.fromJson(Map<String, dynamic> json) {
    return PostAuthor(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: json['name'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{'id': id, 'name': name};
}

/// 一条社区帖子。
///
/// 列表接口只返回 [summary]，详情接口才返回 [content] ——
/// 与知识卡片一样，一个模型两个深度。判断手上这份是不是完整的，
/// 看 [content] 是否为空即可。
class PostItem {
  const PostItem({
    required this.id,
    required this.title,
    this.summary = '',
    this.content = '',
    this.categoryId,
    this.author,
    this.likeCount = 0,
    this.commentCount = 0,
    this.createdAt,
  });

  final int id;
  final String title;

  /// 正文摘要。后端由 `content` 截断而来，不是独立字段，
  /// 因此永远与正文一致。
  final String summary;

  /// 正文。**列表接口不返回该字段**，详情接口才返回。
  final String content;

  /// 帖子可以不属于任何分类，此时为 `null`
  final int? categoryId;

  final PostAuthor? author;
  final int likeCount;

  /// 评论数。详情页的评论区是阶段 12b，
  /// 目前这个数字只用于展示，点进去还看不到评论列表。
  final int commentCount;

  final DateTime? createdAt;

  /// 所属分类，找不到或不属于任何分类时返回 `null`
  SafetyCategory? get category =>
      categoryId == null ? null : categoryById(categoryId!);

  /// 分类显示名，没有分类时返回空串（界面据此决定要不要画那个标签）
  String get categoryName => category?.name ?? '';

  /// 作者署名，拿不到时显示「匿名用户」而不是空白
  String get authorName => author?.name ?? '匿名用户';

  /// 是否带正文（即这份数据来自详情接口）
  bool get hasContent => content.isNotEmpty;

  /// 从后端 JSON 构造。
  ///
  /// 对缺失字段做了容错，避免后端字段调整导致客户端崩溃。
  factory PostItem.fromJson(Map<String, dynamic> json) {
    final Object? author = json['author'];
    return PostItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: json['title'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      content: json['content'] as String? ?? '',
      categoryId: (json['category_id'] as num?)?.toInt(),
      author: author is Map<String, dynamic>
          ? PostAuthor.fromJson(author)
          : null,
      likeCount: (json['like_count'] as num?)?.toInt() ?? 0,
      commentCount: (json['comment_count'] as num?)?.toInt() ?? 0,
      // 后端存的是 naive UTC，必须按 UTC 解释再转本地 ——
      // 直接用 DateTime.parse 会让 UTC+8 的用户看到偏 8 小时的时间
      createdAt: parseServerTime(json['created_at'] as String?),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'summary': summary,
        'content': content,
        'category_id': categoryId,
        'author': author?.toJson(),
        'like_count': likeCount,
        'comment_count': commentCount,
        'created_at': createdAt?.toIso8601String(),
      };
}
