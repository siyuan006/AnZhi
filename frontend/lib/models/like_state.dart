/// 安知 —— 点赞结果
///
/// 字段与 `backend/app/schemas/post.py` 的 `LikeState` 严格对应。
///
/// 点赞和取消点赞都返回它，而**不只是**「操作成功」。原因是爱心旁边
/// 就显示着数字：只回一个 204 的话，客户端只能自己猜加一还是减一，
/// 别人同时点赞时就会越猜越错。回传服务端算好的当前值，
/// 显示的数字永远和数据库里的一致。
class LikeState {
  const LikeState({required this.likeCount, required this.isLiked});

  /// 当前点赞总数（所有人）
  final int likeCount;

  /// 当前这个人点没点过
  final bool isLiked;

  factory LikeState.fromJson(Map<String, dynamic> json) {
    return LikeState(
      likeCount: (json['like_count'] as num?)?.toInt() ?? 0,
      isLiked: json['is_liked'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'like_count': likeCount,
        'is_liked': isLiked,
      };
}
