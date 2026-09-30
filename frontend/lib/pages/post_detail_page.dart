import 'package:flutter/material.dart';

import '../core/app_constants.dart';
import '../core/app_theme.dart';
import '../core/auth_controller.dart';
import '../core/relative_time.dart';
import '../models/comment_item.dart';
import '../models/paged_result.dart';
import '../models/post_item.dart';
import '../services/api_client.dart';
import '../services/post_api.dart';
import '../widgets/async_status.dart';

/// 安知 —— 帖子详情页（阶段 12a 正文，12b 评论，PROJECT_SPEC 第四十一节）
///
/// 链路：`GET /api/posts/{id}` → 正文；`GET/POST /api/posts/{id}/comments` → 评论。
///
/// 列表页点进来时会把那一条（只有标题和摘要）带过来，
/// 页头因此能立刻画出来 —— 用户看到的是自己点的东西，
/// 而不是一整页的转圈。
///
/// **点赞是后续阶段（12c）。** 这里如实显示，而不是画一个点了没反应的按钮。
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

  final TextEditingController _input = TextEditingController();
  final FocusNode _inputFocus = FocusNode();

  PostItem? _item;
  String? _error;
  bool _loading = true;

  List<CommentItem> _comments = <CommentItem>[];
  bool _commentsLoading = true;
  String? _commentsError;
  int _commentTotal = 0;

  bool _sending = false;

  @override
  void initState() {
    super.initState();
    // 先用列表带来的那一条把页头画出来，正文的位置留给加载状态
    _item = widget.preview;
    _load();
    _loadComments();
  }

  @override
  void dispose() {
    _input.dispose();
    _inputFocus.dispose();
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

  Future<void> _loadComments() async {
    setState(() {
      _commentsLoading = true;
      _commentsError = null;
    });

    try {
      final PagedResult<CommentItem> page =
          await _api.fetchComments(widget.postId, pageSize: 50);
      if (!mounted) return;
      setState(() {
        _comments = page.items;
        _commentTotal = page.total;
        _commentsLoading = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _commentsLoading = false;
        _commentsError = error.message;
      });
    }
  }

  Future<void> _send() async {
    final String text = _input.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);

    try {
      final CommentItem created = await _api.postComment(widget.postId, text);
      if (!mounted) return;
      _input.clear();
      setState(() {
        _comments = <CommentItem>[..._comments, created];
        _commentTotal += 1;
        _sending = false;
        _commentsError = null;
      });
      FocusScope.of(context).unfocus();
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
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
              label: '$_commentTotal',
              tooltip: '评论',
              onTap: () => FocusScope.of(context).requestFocus(_inputFocus),
            ),
          ],
        ),
        const SizedBox(height: 24),

        Text(
          '评论 $_commentTotal',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: 14.5,
          ),
        ),
        const SizedBox(height: 12),
        _buildComments(theme),
        const SizedBox(height: 16),
        _buildComposer(theme),
      ],
    );
  }

  Widget _buildComments(ThemeData theme) {
    if (_commentsLoading) {
      return const LoadingPlaceholder(message: '正在加载评论…');
    }
    if (_commentsError != null) {
      return ErrorPlaceholder(message: _commentsError!, onRetry: _loadComments);
    }
    if (_comments.isEmpty) {
      return const _CommentNotice(message: '还没有人评论，来说两句吧');
    }

    return Column(
      children: <Widget>[
        for (final CommentItem comment in _comments)
          _CommentTile(comment: comment),
      ],
    );
  }

  Widget _buildComposer(ThemeData theme) {
    final bool loggedIn = AuthScope.maybeOf(context)?.isLoggedIn ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: _input,
                focusNode: _inputFocus,
                maxLines: 3,
                minLines: 1,
                maxLength: 500,
                enabled: loggedIn && !_sending,
                decoration: InputDecoration(
                  hintText: loggedIn ? '说点什么…' : '登录后可以发表评论',
                  counterText: '',
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton(
              onPressed: loggedIn && !_sending ? _send : null,
              child: _sending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('发表'),
            ),
          ],
        ),
        if (!loggedIn) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            '登录后可以参与讨论',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
  }
}

class _CommentNotice extends StatelessWidget {
  const _CommentNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
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
            size: 26,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({required this.comment});

  final CommentItem comment;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          CircleAvatar(
            radius: 14,
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Text(
              comment.initial,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        comment.authorName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      formatRelativeTime(comment.createdAt),
                      style: TextStyle(
                        fontSize: 11.5,
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  comment.content,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 13.5,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
