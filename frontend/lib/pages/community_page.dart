import 'package:flutter/material.dart';

import '../core/app_constants.dart';
import '../core/app_theme.dart';
import '../core/relative_time.dart';
import '../models/paged_result.dart';
import '../models/post_item.dart';
import '../services/api_client.dart';
import '../services/post_api.dart';
import '../widgets/async_status.dart';
import 'post_detail_page.dart';

/// 安知 —— 社区页（阶段 12a，PROJECT_SPEC 第二十、四十一节）
///
/// V1.0 保持轻量：帖子列表 · 帖子详情 · 发布帖子 · 评论 · 点赞。
/// 暂不实现：私信、关注用户、复杂推荐、AI 审核。
///
/// 阶段 12a 只做**读**：列表与详情。点赞按钮、发帖按钮与评论入口
/// 如实标注后续阶段 —— 做成「点了没反应」比标出来更糟。
///
/// 数据来源 `GET /api/posts`，**不需要登录**：社区内容是公开的。
class CommunityPage extends StatefulWidget {
  const CommunityPage({super.key, this.api});

  /// 允许注入，便于测试用假后端替换真实网络
  final PostApi? api;

  @override
  State<CommunityPage> createState() => _CommunityPageState();
}

class _CommunityPageState extends State<CommunityPage> {
  late final PostApi _api = widget.api ?? PostApi();

  bool _loading = true;
  String? _error;
  List<PostItem> _items = const <PostItem>[];
  int _total = 0;
  int _page = 1;
  bool _loadingMore = false;

  static const int _pageSize = 20;

  bool get _hasMore => _items.length < _total;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    // 只关自己 new 出来的那个；注入进来的由注入方负责
    if (widget.api == null) _api.dispose();
    super.dispose();
  }

  Future<void> _load({bool showLoading = true}) async {
    if (showLoading && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final PagedResult<PostItem> result =
          await _api.fetchPosts(page: 1, pageSize: _pageSize);
      if (!mounted) return;
      setState(() {
        _items = result.items;
        _total = result.total;
        _page = 1;
        _loading = false;
        _error = null;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.message;
      });
    }
  }

  /// 加载下一页。失败时保留已有内容，只在底部提示 ——
  /// 让已经读到的帖子因为翻页失败而消失是不合理的。
  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);

    try {
      final PagedResult<PostItem> result =
          await _api.fetchPosts(page: _page + 1, pageSize: _pageSize);
      if (!mounted) return;
      setState(() {
        _items = <PostItem>[..._items, ...result.items];
        _total = result.total;
        _page += 1;
        _loadingMore = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      _toast(error.message);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _openDetail(PostItem post) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => PostDetailPage(postId: post.id, preview: post),
      ),
    );
    // 回来时刷新：点赞数和评论数可能已经变了
    if (mounted) await _load(showLoading: false);
  }

  /// 功能未实现的统一提示。
  /// 明确告知所处阶段，避免用户以为功能已可用但没有响应。
  void _notYet(String feature, String stage) {
    _toast('「$feature」将在$stage实现');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackgroundColor,
      appBar: AppBar(
        title: const Text('社区'),
        actions: <Widget>[
          IconButton(
            onPressed: () => _notYet('搜索帖子', '后续版本'),
            icon: const Icon(Icons.search_rounded, size: 21),
            tooltip: '搜索帖子',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _notYet('发布帖子', '阶段 12d'),
        icon: const Icon(Icons.edit_outlined, size: 19),
        label: const Text('发帖'),
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(showLoading: false),
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const _Centered(child: LoadingPlaceholder(message: '正在加载帖子…'));
    }

    final String? error = _error;
    if (error != null) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(
          kPagePadding,
          16,
          kPagePadding,
          kPagePadding,
        ),
        children: <Widget>[
          ErrorPlaceholder(
            message: error,
            hint: '确认后端已启动，然后重试。',
            onRetry: _load,
          ),
        ],
      );
    }

    if (_items.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(
          kPagePadding,
          40,
          kPagePadding,
          kPagePadding,
        ),
        children: const <Widget>[
          EmptyPlaceholder(
            title: '还没有人发帖',
            message: '这里会显示同学们分享的安全经验。\n你可以点右下角的「发帖」做第一个。',
            icon: Icons.forum_outlined,
          ),
        ],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(kPagePadding, 12, kPagePadding, 88),
      itemCount: _items.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: kCardGap),
      itemBuilder: (BuildContext context, int index) {
        if (index == _items.length) return _buildFooter();
        final PostItem post = _items[index];
        return _PostCard(
          post: post,
          onTap: () => _openDetail(post),
          onLike: () => _notYet('点赞', '阶段 12c'),
          onComment: () => _openDetail(post),
        );
      },
    );
  }

  Widget _buildFooter() {
    if (_loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2.2),
          ),
        ),
      );
    }
    if (_hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: OutlinedButton(
            onPressed: _loadMore,
            child: const Text('加载更多'),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: Text(
          '共 $_total 条帖子',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.outline,
          ),
        ),
      ),
    );
  }
}

/// 让占位组件在填满屏幕的列表里也保持垂直居中
class _Centered extends StatelessWidget {
  const _Centered({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(child: child),
          ),
        );
      },
    );
  }
}

class _PostCard extends StatelessWidget {
  const _PostCard({
    required this.post,
    required this.onTap,
    required this.onLike,
    required this.onComment,
  });

  final PostItem post;
  final VoidCallback onTap;
  final VoidCallback onLike;
  final VoidCallback onComment;

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
              // 作者 + 时间 + 分类
              Row(
                children: <Widget>[
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Text(
                      post.author?.initial ?? '?',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      post.authorName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    formatRelativeTime(post.createdAt),
                    style: TextStyle(
                      fontSize: 11.5,
                      color: theme.colorScheme.outline,
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

              // 正文摘要（后端已截断，这里再按行数兜一层）
              Text(
                post.summary,
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
                    onTap: onComment,
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
