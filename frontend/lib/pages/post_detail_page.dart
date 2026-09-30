import 'package:flutter/material.dart';

import '../core/app_constants.dart';
import '../core/app_theme.dart';
import '../core/relative_time.dart';
import '../models/post_item.dart';
import '../services/api_client.dart';
import '../services/post_api.dart';
import '../widgets/async_status.dart';

/// 安知 —— 帖子详情页（阶段 12a，PROJECT_SPEC 第四十一节）
///
/// 链路：`GET /api/posts/{id}` → 正文。
///
/// 列表页点进来时会把那一条（只有标题和摘要）带过来，
/// 页头因此能立刻画出来 —— 用户看到的是自己点的东西，
/// 而不是一整页的转圈。
///
/// **评论区与点赞是后续阶段。** 这里如实显示「评论功能在阶段 12b」，
/// 而不是画一个假评论区或者一个点了没反应的按钮。
class PostDetailPage extends StatefulWidget {
  const PostDetailPage({
    super.key,
    required this.postId,
    this.preview,
    this.api,
  });

  final int postId;

  /// 列表页带过来的那一条，只有标题与摘要，没有正文
  final PostItem? preview;

  /// 允许注入，便于测试用假后端替换真实网络
  final PostApi? api;

  @override
  State<PostDetailPage> createState() => _PostDetailPageState();
}

class _PostDetailPageState extends State<PostDetailPage> {
  late final PostApi _api = widget.api ?? PostApi();

  PostItem? _item;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    // 先用列表带来的那一条把页头画出来，正文的位置留给加载状态
    _item = widget.preview;
    _load();
  }

  @override
  void dispose() {
    // 只关自己 new 出来的那个；注入进来的由注入方负责
    if (widget.api == null) _api.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final PostItem item = await _api.fetchPostDetail(widget.postId);
      if (!mounted) return;
      setState(() {
        _item = item;
        _loading = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.message;
      });
    }
  }

  void _notYet(String feature, String stage) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('「$feature」将在$stage实现'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final PostItem? item = _item;

    return Scaffold(
      backgroundColor: kBackgroundColor,
      appBar: AppBar(title: const Text('帖子')),
      body: _buildBody(item),
    );
  }

  Widget _buildBody(PostItem? item) {
    // 完全没有数据可显示（直接进详情、且请求失败）时才整页报错
    if (item == null) {
      if (_loading) {
        return const Center(child: LoadingPlaceholder(message: '正在加载帖子…'));
      }
      return ListView(
        padding: const EdgeInsets.all(kPagePadding),
        children: <Widget>[
          ErrorPlaceholder(
            message: _error ?? '帖子不存在或已删除',
            onRetry: _load,
          ),
        ],
      );
    }

    final ThemeData theme = Theme.of(context);
    final SafetyCategory? category = item.category;

    return ListView(
      padding: const EdgeInsets.fromLTRB(kPagePadding, 16, kPagePadding, 32),
      children: <Widget>[
        // 标题
        Text(
          item.title,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: 20,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 14),

        // 作者 · 时间 · 分类
        Row(
          children: <Widget>[
            CircleAvatar(
              radius: 16,
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Text(
                item.author?.initial ?? '?',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(width: 9),
            Flexible(
              child: Text(
                item.authorName,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              formatRelativeTime(item.createdAt),
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.outline,
              ),
            ),
            const Spacer(),
            if (category != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: category.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  category.name,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: category.color,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 18),
        const Divider(height: 1),
        const SizedBox(height: 18),

        // 正文
        if (_loading)
          const LoadingPlaceholder(message: '正在加载正文…')
        else if (_error != null)
          ErrorPlaceholder(message: _error!, onRetry: _load)
        else
          SelectableText(
            item.content,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 14.5,
              height: 1.85,
            ),
          ),

        const SizedBox(height: 26),
        const Divider(height: 1),
        const SizedBox(height: 14),

        // 互动。两个都是后续阶段，如实标注。
        Row(
          children: <Widget>[
            _ActionButton(
              icon: Icons.favorite_border_rounded,
              label: '${item.likeCount}',
              tooltip: '点赞',
              onTap: () => _notYet('点赞', '阶段 12c'),
            ),
            const SizedBox(width: 12),
            _ActionButton(
              icon: Icons.chat_bubble_outline_rounded,
              label: '${item.commentCount}',
              tooltip: '评论',
              onTap: () => _notYet('评论', '阶段 12b'),
            ),
          ],
        ),
        const SizedBox(height: 22),

        // 评论区占位。明确说明而不是留白 ——
        // 用户看到一个空的区域会以为是加载失败。
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
          decoration: BoxDecoration(
            color: kSurfaceColor,
            borderRadius: BorderRadius.circular(kCardRadius),
          ),
          child: Column(
            children: <Widget>[
              Icon(
                Icons.forum_outlined,
                size: 28,
                color: theme.colorScheme.outline,
              ),
              const SizedBox(height: 10),
              Text(
                '评论区将在阶段 12b 开放',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 13.5,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '发帖与评论功能还在开发中，\n目前可以正常浏览大家分享的内容。',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 17),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
