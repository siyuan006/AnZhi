import '../core/relative_time.dart';
import 'post_item.dart';

/// 安知 —— 帖子评论数据模型
///
/// 字段与 `backend/app/schemas/comment.py` 严格对应。
class CommentItem {
  const CommentItem({
    required this.id,
    required this.content,
    this.author,
    this.createdAt,
  });

  final int id;
  final String content;
  final PostAuthor? author;
  final DateTime? createdAt;

  String get authorName => author?.name ?? '匿名用户';

  String get initial => author?.initial ?? '?';

  factory CommentItem.fromJson(Map<String, dynamic> json) {
    final Object? rawAuthor = json['author'];
    return CommentItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      content: json['content'] as String? ?? '',
      author: rawAuthor is Map<String, dynamic>
          ? PostAuthor.fromJson(rawAuthor)
          : null,
      createdAt: parseServerTime(json['created_at'] as String?),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'content': content,
        'author': author?.toJson(),
        'created_at': createdAt?.toIso8601String(),
      };
}
