import 'package:flutter/material.dart';

import '../core/app_constants.dart';
import '../core/app_theme.dart';
import '../core/auth_controller.dart';
import '../models/favorite_item.dart';
import '../models/paged_result.dart';
import '../services/api_client.dart';
import '../services/favorite_api.dart';
import '../widgets/async_status.dart';
import '../widgets/knowledge_tile.dart';
import 'knowledge_detail_page.dart';
import 'login_page.dart';

/// 安知 —— 我的收藏（阶段 11b，PROJECT_SPEC 第三十九节）
///
/// 数据来源 `GET /api/favorites`。只有登录后才有内容 ——
/// 未登录时本页如实显示「请先登录」并给一个入口，
/// 而不是显示「暂无收藏」（那是在骗用户：不是没有，是不知道你是谁）。
///
/// 列表里显示的标题、分类、风险等级都由后端随收藏记录一并返回
/// （见 `models/favorite_item.dart`），不需要为每一行再查一次详情。
class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key, this.api});

  /// 允许注入，便于测试用假后端替换真实网络
  final FavoriteApi? api;

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  FavoriteApi? _api;
  bool _started = false;

  bool _loading = true;
  String? _error;
  List<FavoriteItem> _items = const <FavoriteItem>[];
  int _total = 0;
  int _page = 1;
  bool _loadingMore = false;

  /// 正在取消收藏的知识 id，用于把那一行的按钮置灰。
  final Set<int> _removing = <int>{};

  static const int _pageSize = 20;

  bool get _hasMore => _items.length < _total;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;

    // 收藏接口必须带着当前 token，所以从 AuthScope 取 ——
    // 自己 new 一个会是匿名客户端，只会拿到 401。
    _api = widget.api ?? AuthScope.maybeOf(context)?.favoriteApi;
    _load();
  }

  bool get _isLoggedIn => AuthScope.maybeOf(context)?.isLoggedIn ?? false;

  Future<void> _load({bool showLoading = true}) async {
    final FavoriteApi? api = _api;
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
      final PagedResult<FavoriteItem> result =
          await api.fetchFavorites(page: 1, pageSize: _pageSize);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = null;
        _items = result.items;
        _total = result.total;
        _page = 1;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.message;
        _items = const <FavoriteItem>[];
        _total = 0;
      });
    }
  }

  Future<void> _loadMore() async {
    final FavoriteApi? api = _api;
    if (api == null || _loadingMore || !_hasMore) return;

    setState(() => _loadingMore = true);
    try {
      final PagedResult<FavoriteItem> result =
          await api.fetchFavorites(page: _page + 1, pageSize: _pageSize);
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        _page += 1;
        _items = <FavoriteItem>[..._items, ...result.items];
        _total = result.total;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      _toast(error.message);
    }
  }

  /// 在本页直接取消收藏。
  ///
  /// 成功后**从列表里移除这一行并让 total 减一** —— 用户刚说了不要它，
  /// 还留在原地只会让人以为没生效。失败则原样不动并说明原因。
  Future<void> _remove(FavoriteItem item) async {
    final FavoriteApi? api = _api;
    if (api == null || _removing.contains(item.knowledgeId)) return;

    setState(() => _removing.add(item.knowledgeId));
    try {
      await api.remove(item.knowledgeId);
      if (!mounted) return;
      setState(() {
        _removing.remove(item.knowledgeId);
        _items = _items
            .where((FavoriteItem row) => row.knowledgeId != item.knowledgeId)
            .toList(growable: false);
        if (_total > 0) _total -= 1;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _removing.remove(item.knowledgeId));
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

  /// 打开详情页，回来后**刷新一次**。
  ///
  /// 用户可能在详情页里取消了收藏 —— 不刷新的话列表里会留着一行
  /// 已经不在收藏里的内容。
  Future<void> _openDetail(FavoriteItem item) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => KnowledgeDetailPage(
          knowledgeId: item.knowledgeId,
          preview: item.knowledge,
        ),
      ),
    );
    if (!mounted) return;
    await _load(showLoading: false);
  }

  Future<void> _openLogin() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const LoginPage()),
    );
    if (!mounted) return;
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackgroundColor,
      appBar: AppBar(
        title: const Text('我的收藏'),
        actions: <Widget>[
          if (_isLoggedIn && _items.isNotEmpty)
            IconButton(
              tooltip: '刷新',
              onPressed: () => _load(showLoading: false),
              icon: const Icon(Icons.refresh_rounded),
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    // 未登录（包括在本页停留时被登出）：如实说明，并给一个入口。
    // 显示「暂无收藏」是不对的 —— 不是没有，是不知道你是谁。
    if (!_isLoggedIn) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(kPagePadding),
        child: Column(
          children: <Widget>[
            const EmptyPlaceholder(
              icon: Icons.bookmark_border_rounded,
              title: '请先登录',
              message: '收藏是按账号保存的。登录后就能看到你收藏过的内容。',
            ),
            // 给一条回来的路：用户可能是在这一页停留时被登出的
            OutlinedButton(
              onPressed: _openLogin,
              child: const Text('去登录'),
            ),
          ],
        ),
      );
    }

    if (_loading) {
      return const LoadingPlaceholder(message: '正在加载收藏…');
    }

    if (_error != null) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(kPagePadding, 8, kPagePadding, 24),
        child: ErrorPlaceholder(
          message: _error!,
          hint: '收藏来自后端服务，请确认后端已启动',
          onRetry: _load,
        ),
      );
    }

    if (_items.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _load(showLoading: false),
        child: ListView(
          // 内容不足一屏时列表默认不可滚动，空状态也要能下拉刷新
          physics: const AlwaysScrollableScrollPhysics(),
          children: const <Widget>[
            SizedBox(height: 60),
            EmptyPlaceholder(
              icon: Icons.bookmark_border_rounded,
              title: '还没有收藏',
              message: '在知识详情页点右上角的书签，\n收藏的内容就会出现在这里。',
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _load(showLoading: false),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(kPagePadding, 0, kPagePadding, 24),
        itemCount: _items.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: kCardGap),
        itemBuilder: (BuildContext context, int index) {
          if (index == _items.length) return _buildFooter();
          return _buildRow(_items[index]);
        },
      ),
    );
  }

  Widget _buildRow(FavoriteItem item) {
    final bool busy = _removing.contains(item.knowledgeId);

    // 后端理论上不会给出没有嵌套知识的收藏（列表用 INNER JOIN 过滤过），
    // 但真出现了就如实说明，而不是渲染一行空白让人以为界面坏了。
    if (item.isBroken) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: kSurfaceColor,
          borderRadius: BorderRadius.circular(kCardRadius),
        ),
        child: const Text(
          '这条内容已下架',
          style: TextStyle(fontSize: 13.5, color: Color(0xFF9AA4B2)),
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Expanded(
          child: KnowledgeTile(
            item: item.knowledge,
            onTap: () => _openDetail(item),
          ),
        ),
        IconButton(
          onPressed: busy ? null : () => _remove(item),
          tooltip: '取消收藏',
          icon: const Icon(Icons.bookmark_remove_outlined),
        ),
      ],
    );
  }

  Widget _buildFooter() {
    if (_hasMore) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Center(
          child: _loadingMore
              ? const LoadingPlaceholder(message: '正在加载更多…')
              : OutlinedButton(
                  onPressed: _loadMore,
                  child: Text('加载更多（还有 ${_total - _items.length} 条）'),
                ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Center(
        child: Text(
          '共 $_total 条收藏',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.outline,
          ),
        ),
      ),
    );
  }
}
