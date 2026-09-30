import 'package:flutter/material.dart';

import '../core/app_constants.dart';
import '../core/app_theme.dart';
import '../core/sample_data.dart';

/// 安知 —— 社区页
///
/// V1.0 保持轻量（PROJECT_SPEC 第二十节）：
///   帖子列表 · 帖子详情 · 发布帖子 · 评论 · 点赞
///
/// 暂不实现：私信、关注用户、复杂推荐、AI 审核。
///
/// ⚠️ 当前为占位数据，阶段 12「社区」实现真实接口后替换。
class CommunityPage extends StatelessWidget {
  const CommunityPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackgroundColor,
      appBar: AppBar(title: const Text('社区')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _notYet(context, '发布帖子'),
        icon: const Icon(Icons.edit_outlined, size: 19),
        label: const Text('发帖'),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(
          kPagePadding,
          4,
          kPagePadding,
          88,
        ),
        itemCount: kSamplePosts.length,
        separatorBuilder: (_, _) => const SizedBox(height: kCardGap),
        itemBuilder: (BuildContext context, int index) {
          return _PostCard(
            post: kSamplePosts[index],
            onTap: () => _notYet(context, '帖子详情'),
            onLike: () => _notYet(context, '点赞'),
          );
        },
      ),
    );
  }

  /// 功能未实现的统一提示。
  /// 明确告知所处阶段，避免用户以为功能已可用但没有响应。
  void _notYet(BuildContext context, String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('「$feature」将在阶段 12 实现'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

class _PostCard extends StatelessWidget {
  const _PostCard({
    required this.post,
    required this.onTap,
    required this.onLike,
  });

  final SamplePost post;
  final VoidCallback onTap;
  final VoidCallback onLike;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final SafetyCategory? category = post.category;

    return Material(
      color: kSurfaceColor,
      borderRadius: BorderRadius.circular(kCardRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(kCardRadius),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // 作者 + 分类
              Row(
                children: <Widget>[
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Text(
                      post.author.characters.first,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    post.author,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  if (category != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: category.color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        category.name,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: category.color,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 11),

              // 标题
              Text(
                post.title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  height: 1.4,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),

              // 正文摘要
              Text(
                post.content,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.55,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 8),

              // 互动
              Row(
                children: <Widget>[
                  _ActionIcon(
                    icon: Icons.favorite_border_rounded,
                    label: '${post.likeCount}',
                    onTap: onLike,
                  ),
                  const SizedBox(width: 20),
                  _ActionIcon(
                    icon: Icons.chat_bubble_outline_rounded,
                    label: '${post.commentCount}',
                    onTap: onTap,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionIcon extends StatelessWidget {
  const _ActionIcon({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color color = Theme.of(context).colorScheme.outline;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(fontSize: 12.5, color: color),
            ),
          ],
        ),
      ),
    );
  }
}
