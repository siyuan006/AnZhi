import 'package:flutter/material.dart';

import '../core/app_constants.dart';
import '../core/app_theme.dart';
import '../core/auth_controller.dart';
import '../core/relative_time.dart';
import '../models/history_item.dart';
import '../models/paged_result.dart';
import '../services/api_client.dart';
import '../services/history_api.dart';
import '../widgets/async_status.dart';
import '../widgets/knowledge_tile.dart';
import 'knowledge_detail_page.dart';
import 'login_page.dart';

/// 安知 —— 浏览历史（阶段 11c，PROJECT_SPEC 第四十节）
///
/// 数据来源 `GET /api/history`。只有登录后才有内容 ——
/// 未登录时本页如实显示「请先登录」并给一个入口，
/// 而不是显示「暂无浏览记录」（那是在骗用户：不是没有，是不知道你是谁）。
///
/// **记录浏览不在这里**：用户打开知识详情页时会调
/// `POST /api/knowledge/{id}/view`，后端带着可选登录身份顺手把历史写好
/// （见 `services/history_api.dart` 的说明）。本页只管读和删。
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key, this.api});

  /// 允许注入，便于测试用假后端替换真实网络
  final HistoryApi? api;

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  HistoryApi? _api;
  bool _started = false;

  bool _loading = true;
  String? _error;
  List<HistoryItem> _items = const <HistoryItem>[];
  int _total = 0;
  int _page = 1;
  bool _loadingMore = false;
  bool _clearing = false;

  /// 正在删除的知识 id，用于把那一行的按钮置灰。
  final Set<int> _removing = <int>{};

  static const int _pageSize = 20;

  bool get _hasMore => _items.length < _total;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;

    // 历史接口必须带着当前 token，所以从 AuthScope 取 ——
    // 自己 new 一个会是匿名客户端，只会拿到 401。
    _api = widget.api ?? AuthScope.maybeOf(context)?.historyApi;
    _load();
  }

  bool get _isLoggedIn => AuthScope.maybeOf(context)?.isLoggedIn ?? false;

  Future<void> _load({bool showLoading = true}) async {
    final HistoryApi? api = _api;
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
      final PagedResult<HistoryItem> result =
          await api.fetchHistory(page: 1, pageSize: _pageSize);
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
        _items = const <HistoryItem>[];
        _total = 0;
      });
    }
  }

  Future<void> _loadMore() async {
    final HistoryApi? api = _api;
    if (api == null || _loadingMore || !_hasMore) return;

    setState(() => _loadingMore = true);
    try {
      final PagedResult<HistoryItem> result =
          await api.fetchHistory(page: _page + 1, pageSize: _pageSize);
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        _page += 1;
        _items = <HistoryItem>[..._items, ...result.items];
        _total = result.total;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      _toast(error.message);
    }
  }

  /// 删掉这一条。
  ///
  /// 成功后**从列表里移除这一行并让 total 减一** —— 用户刚说了不要它，
  /// 还留在原地只会让人以为没生效。失败则原样不动并说明原因。
  Future<void> _remove(HistoryItem item) async {
    final HistoryApi? api = _api;
    if (api == null || _removing.contains(item.knowledgeId)) return;

    setState(() => _removing.add(item.knowledgeId));
    try {
      await api.remove(item.knowledgeId);
      if (!mounted) return;
      setState(() {
        _removing.remove(item.knowledgeId);
        _items = _items
            .where((HistoryItem row) => row.knowledgeId != item.knowledgeId)
            .toList(growable: false);
        if (_total > 0) _total -= 1;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _removing.remove(item.knowledgeId));
      _toast(error.message);
    }
  }

  /// 清空全部。**先问一句** —— 这是本页唯一不可撤销的操作。
  Future<void> _clearAll() async {
    final HistoryApi? api = _api;
    if (api == null || _clearing || _items.isEmpty) return;

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('清空浏览历史'),
          content: Text('将删除全部 $_total 条浏览记录，且无法恢复。'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('清空'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    setState(() => _clearing = true);
    try {
      await api.clear();
      if (!mounted) return;
      setState(() {
        _clearing = false;
        _items = const <HistoryItem>[];
        _total = 0;
        _page = 1;
      });
      _toast('浏览历史已清空');
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _clearing = false);
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
  /// 用户刚看过的这一条时间会被推到最前 —— 不刷新的话列表顺序
  /// 和他刚才的操作对不上。
  Future<void> _openDetail(HistoryItem item) async {
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
        title: const Text('浏览历史'),
        actions: <Widget>[
          if (_isLoggedIn && _items.isNotEmpty)
            IconButton(
              tooltip: '清空浏览历史',
              onPressed: _clearing ? null : _clearAll,
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    // 未登录（包括在本页停留时被登出）：如实说明，并给一个入口。
    // 显示「暂无浏览记录」是不对的 —— 不是没有，是不知道你是谁。
    if (!_isLoggedIn) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(kPagePadding),
        child: Column(
          children: <Widget>[
            const EmptyPlaceholder(
              icon: Icons.history_rounded,
              title: '请先登录',
              message: '浏览历史是按账号保存的。登录后就能看到你读过的内容。',
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
      return const LoadingPlaceholder(message: '正在加载浏览历史…');
    }

    if (_error != null) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(kPagePadding, 8, kPagePadding, 24),
        child: ErrorPlaceholder(
          message: _error!,
          hint: '浏览历史来自后端服务，请确认后端已启动',
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
              icon: Icons.history_rounded,
              title: '还没有浏览记录',
              message: '读过的安全知识会自动出现在这里，\n方便你回头再看一遍。',
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

  Widget _buildRow(HistoryItem item) {
    final bool busy = _removing.contains(item.knowledgeId);

    // 后端理论上不会给出没有嵌套知识的历史（列表用 INNER JOIN 过滤过），
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 5),
          child: Text(
            formatRelativeTime(item.viewedAt),
            style: TextStyle(
              fontSize: 11.5,
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ),
        Row(
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
              tooltip: '删除这条记录',
              icon: const Icon(Icons.close_rounded, size: 20),
            ),
          ],
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
          '共 $_total 条浏览记录',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.outline,
          ),
        ),
      ),
    );
  }
}
