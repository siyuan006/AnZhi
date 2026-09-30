import 'package:flutter/material.dart';

import '../core/app_constants.dart';
import '../core/app_theme.dart';
import '../core/auth_controller.dart';
import '../core/relative_time.dart';
import '../models/like_state.dart';
import '../models/paged_result.dart';
import '../models/post_item.dart';
import '../services/api_client.dart';
import '../services/post_api.dart';
import '../widgets/async_status.dart';
import 'post_compose_page.dart';
import 'post_detail_page.dart';

/// 安知 —— 社区页（阶段 12a 列表，12c 点赞，12d 发帖，PROJECT_SPEC 第二十、四十一节）
///
/// V1.0 保持轻量：帖子列表 · 帖子详情 · 发布帖子 · 评论 · 点赞。
/// 暂不实现：私信、关注用户、复杂推荐、AI 审核。
///
/// 数据来源 `GET /api/posts`，**不需要登录**：社区内容是公开的。
/// 带上 token 时每一项会多一个 `is_liked`，爱心因此能如实反映
/// 「我点过没有」—— 而不是所有人看到的都是空心。
///
/// 搜索按钮如实标注后续版本 —— 做成「点了没反应」比标出来更糟。
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

  /// 正在请求中的帖子 id。挡住连点，避免同一条被点出两次请求。
  final Set<int> _liking = <int>{};

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
        builder: (_) => PostDetailPage(
          postId: post.id,
          preview: post,
          api: _api,
        ),
      ),
    );
    // 回来时刷新：点赞数和评论数可能已经变了
    if (mounted) await _load(showLoading: false);
  }

  /// 点赞 / 取消点赞。
  ///
  /// 只替换列表里的那一条，不整页重刷 —— 重刷会让用户正在看的位置
  /// 跳回去。数字与爱心以服务端返回的为准（见 [LikeState]）。
  Future<void> _toggleLike(PostItem post) async {
    if (_liking.contains(post.id)) return;

    final AuthController? auth = AuthScope.maybeOf(context);
    if (auth == null || !auth.isLoggedIn) {
      _toast('登录后可以点赞');
      return;
    }

    setState(() => _liking.add(post.id));

    try {
      final LikeState state =
          post.isLiked ? await _api.unlike(post.id) : await _api.like(post.id);
      if (!mounted) return;
      setState(() {
        _items = <PostItem>[
          for (final PostItem item in _items)
            item.id == post.id ? item.withLike(state) : item,
        ];
        _liking.remove(post.id);
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _liking.remove(post.id));
      _toast(error.message);
    }
  }

  /// 打开发帖页。
  ///
  /// 把当前这个 `_api` 传下去，而不是让它自己造一个 ——
  /// 本页的 `_api` 是带 token 的那个（`app.dart` 里用
  /// `AuthController.apiClient` 建的），发帖要用得上。
  ///
  /// 发成功了才刷新：用户按返回键放弃时不必多打一次请求。
  Future<void> _openCompose() async {
    final AuthController? auth = AuthScope.maybeOf(context);
    if (auth == null || !auth.isLoggedIn) {
      _toast('登录后可以发帖');
      return;
    }

    final PostItem? created = await Navigator.of(context).push<PostItem>(
      MaterialPageRoute<PostItem>(
        builder: (_) => PostComposePage(api: _api),
      ),
    );
    if (!mounted) return;
    if (created != null) await _load(showLoading: false);
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
        onPressed: _openCompose,
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
          onLike: () => _toggleLike(post),
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
                    icon: post.isLiked
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    label: '${post.likeCount}',
                    active: post.isLiked,
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
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// 已点赞时高亮。图标形状同时会变（实心 / 空心）——
  /// 只换颜色的话，色觉障碍用户看不出区别。
  final bool active;

  @override
  Widget build(BuildContext context) {
    final Color color = active
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.outline;

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
