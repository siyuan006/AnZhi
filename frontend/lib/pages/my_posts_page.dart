import 'package:flutter/material.dart';

import '../core/app_constants.dart';
import '../core/app_theme.dart';
import '../core/auth_controller.dart';
import '../core/relative_time.dart';
import '../models/paged_result.dart';
import '../models/post_item.dart';
import '../services/api_client.dart';
import '../services/post_api.dart';
import '../widgets/async_status.dart';
import 'login_page.dart';
import 'post_compose_page.dart';
import 'post_detail_page.dart';

/// 安知 —— 我的帖子（阶段 12d，PROJECT_SPEC 第二十节）
///
/// 数据来源 `GET /api/posts/mine`。与「我的收藏」一样，这是
/// 「这份数据属于谁」的接口，未登录时如实说明并给一个入口，
/// 而不是显示「还没有发过帖子」—— 那是在骗用户：不是没有，
/// 是不知道你是谁。
///
/// 删除是**软删除**（后端把 `is_published` 置为 False），
/// 但对用户而言就是删掉了：删完这一行立刻从列表消失。
class MyPostsPage extends StatefulWidget {
  const MyPostsPage({super.key, this.api});

  /// 允许注入，便于测试用假后端替换真实网络
  final PostApi? api;

  @override
  State<MyPostsPage> createState() => _MyPostsPageState();
}

class _MyPostsPageState extends State<MyPostsPage> {
  /// 没注入时借用 `AuthScope` 那个带 token 的客户端，不自己造一个 ——
  /// 本页的接口全都要登录，匿名客户端只会拿到 401。
  ///
  /// 在 `didChangeDependencies` 里取而不是 `initState`：`AuthScope.maybeOf`
  /// 要读 InheritedWidget，在 `initState` 里读会被框架断言拦下
  /// （而且那里读到的依赖变化也不会被重建）。
  PostApi? _api;
  bool _started = false;

  bool _loading = true;
  String? _error;
  List<PostItem> _items = const <PostItem>[];
  int _total = 0;
  int _page = 1;
  bool _loadingMore = false;

  /// 正在删除的帖子 id，用于把那一行置灰并挡住连点
  final Set<int> _deleting = <int>{};

  static const int _pageSize = 20;

  bool get _hasMore => _items.length < _total;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;

    _api = widget.api ?? PostApi(client: AuthScope.maybeOf(context)?.apiClient);
    _load();
  }

  @override
  void dispose() {
    // 只关自己 new 出来的那个；注入进来的由注入方负责
    if (widget.api == null) _api?.dispose();
    super.dispose();
  }

  bool get _isLoggedIn => AuthScope.maybeOf(context)?.isLoggedIn ?? false;

  Future<void> _load({bool showLoading = true}) async {
    final PostApi? api = _api;
    if (api == null) {
      setState(() => _loading = false);
      return;
    }

    if (showLoading && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final PagedResult<PostItem> result =
          await api.fetchMyPosts(page: 1, pageSize: _pageSize);
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
        _items = const <PostItem>[];
        _total = 0;
      });
    }
  }

  Future<void> _loadMore() async {
    final PostApi? api = _api;
    if (api == null || _loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);

    try {
      final PagedResult<PostItem> result =
          await api.fetchMyPosts(page: _page + 1, pageSize: _pageSize);
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
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
      );
  }

  /// 删除前先问一句。
  ///
  /// 删帖在用户看来是不可逆的（后端虽然留着行，但界面里没有任何
  /// 恢复入口），值得多问一次 —— 而且要说清楚**删的是哪一条**，
  /// 只写「确定删除吗」等于让用户凭记忆赌一把。
  Future<bool> _confirmDelete(PostItem post) async {
    final bool? answer = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('删除这条帖子？'),
        content: Text(
          '《${post.title}》\n\n删除后其他人就看不到了，'
          '已有的点赞和评论也会一并隐藏。',
          style: const TextStyle(fontSize: 13.5, height: 1.6),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    return answer ?? false;
  }

  Future<void> _delete(PostItem post) async {
    final PostApi? api = _api;
    if (api == null || _deleting.contains(post.id)) return;
    if (!await _confirmDelete(post)) return;
    if (!mounted) return;

    setState(() => _deleting.add(post.id));

    try {
      await api.deletePost(post.id);
      if (!mounted) return;
      setState(() {
        _deleting.remove(post.id);
        _items = _items
            .where((PostItem row) => row.id != post.id)
            .toList(growable: false);
        if (_total > 0) _total -= 1;
      });
      _toast('已删除');
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _deleting.remove(post.id));
      _toast(error.message);
    }
  }

  /// 打开详情，回来后刷新 —— 点赞数和评论数可能已经变了
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
    if (mounted) await _load(showLoading: false);
  }

  /// 从这里也能发帖 —— 尤其是删光之后，页面上总得有条出路
  Future<void> _openCompose() async {
    final PostItem? created = await Navigator.of(context).push<PostItem>(
      MaterialPageRoute<PostItem>(
        builder: (_) => PostComposePage(api: _api),
      ),
    );
    if (!mounted) return;
    // 发成功了才刷新；用户按返回键放弃时不必多打一次请求
    if (created != null) await _load(showLoading: false);
  }

  Future<void> _openLogin() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const LoginPage()),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackgroundColor,
      appBar: AppBar(
        title: const Text('我的帖子'),
        actions: <Widget>[
          if (_isLoggedIn && _items.isNotEmpty)
            IconButton(
              tooltip: '刷新',
              onPressed: () => _load(showLoading: false),
              icon: const Icon(Icons.refresh_rounded),
            ),
        ],
      ),
      floatingActionButton: _isLoggedIn
          ? FloatingActionButton.extended(
              onPressed: _openCompose,
              icon: const Icon(Icons.edit_outlined, size: 19),
              label: const Text('发帖'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () => _load(showLoading: false),
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (!_isLoggedIn) {
      return ListView(
        padding: const EdgeInsets.all(kPagePadding),
        children: <Widget>[
          const EmptyPlaceholder(
            icon: Icons.article_outlined,
            title: '请先登录',
            message: '帖子是跟着账号走的。登录后就能看到你发过的内容。',
          ),
          OutlinedButton(
            onPressed: _openLogin,
            child: const Text('去登录'),
          ),
        ],
      );
    }

    if (_loading) {
      return const _Centered(child: LoadingPlaceholder(message: '正在加载…'));
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
          96,
        ),
        children: const <Widget>[
          EmptyPlaceholder(
            icon: Icons.article_outlined,
            title: '还没有发过帖子',
            message: '点右下角的「发帖」，把你的安全经验分享给同学。',
          ),
        ],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(kPagePadding, 12, kPagePadding, 96),
      itemCount: _items.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: kCardGap),
      itemBuilder: (BuildContext context, int index) {
        if (index == _items.length) return _buildFooter();
        return _buildRow(_items[index]);
      },
    );
  }

  Widget _buildRow(PostItem post) {
    final ThemeData theme = Theme.of(context);
    final bool busy = _deleting.contains(post.id);
    final SafetyCategory? category = post.category;

    return Opacity(
      // 正在删的那一条变淡：让「点了没反应」和「正在处理」看起来不一样
      opacity: busy ? 0.5 : 1,
      child: Material(
        color: kSurfaceColor,
        borderRadius: BorderRadius.circular(kCardRadius),
        child: InkWell(
          onTap: busy ? null : () => _openDetail(post),
          borderRadius: BorderRadius.circular(kCardRadius),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(15, 14, 6, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
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
                      const SizedBox(height: 7),
                      Row(
                        children: <Widget>[
                          if (category != null) ...<Widget>[
                            Flexible(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: category.color.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  category.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: category.color,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Icon(
                            Icons.favorite_border_rounded,
                            size: 14,
                            color: theme.colorScheme.outline,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '${post.likeCount}',
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.outline,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 14,
                            color: theme.colorScheme.outline,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '${post.commentCount}',
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.outline,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Flexible(
                            child: Text(
                              formatRelativeTime(post.createdAt),
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: theme.colorScheme.outline,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: busy ? null : () => _delete(post),
                  tooltip: '删除',
                  icon: const Icon(Icons.delete_outline_rounded, size: 20),
                ),
              ],
            ),
          ),
        ),
      ),
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
