import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_constants.dart';
import '../core/app_theme.dart';
import '../models/knowledge_item.dart';
import '../models/paged_result.dart';
import '../services/api_client.dart';
import '../services/knowledge_api.dart';
import '../widgets/async_status.dart';
import '../widgets/knowledge_tile.dart';

/// 安知 —— 知识页
///
/// 结构（PROJECT_SPEC 第三十八节）：分类列表 → 知识列表 → 知识详情。
/// 本页承担前两级：顶部分类筛选 + 知识列表；详情页将在阶段 10 实现。
///
/// 数据来源为后端 `GET /api/knowledge`（阶段 7 接通）。
/// 筛选与分页**全部由服务端完成**，客户端只负责渲染返回值 ——
/// 本地过滤会导致「筛出来的条数」和接口返回的 `total` 对不上。
///
/// ⚠️ 后端只返回**已人工审核发布**的内容（PROJECT_SPEC 第十五节），
/// 因此审核完成前这里会如实显示「暂无内容」，这是正确行为而非故障。
class KnowledgePage extends StatefulWidget {
  const KnowledgePage({super.key, this.api});

  /// 允许注入，便于测试用假客户端替换真实网络
  final KnowledgeApi? api;

  @override
  State<KnowledgePage> createState() => _KnowledgePageState();
}

class _KnowledgePageState extends State<KnowledgePage> {
  late final KnowledgeApi _api = widget.api ?? KnowledgeApi();

  /// 是否由本页创建（决定 dispose 时是否要关闭连接）
  late final bool _ownsApi = widget.api == null;

  /// 当前选中的分类 id；`null` 表示「全部」
  int? _selectedCategoryId;

  final TextEditingController _searchController = TextEditingController();
  String _keyword = '';

  /// 搜索防抖：每敲一个字就发一次请求既浪费流量，
  /// 也会让返回顺序错乱。停止输入 350ms 后才真正发起请求。
  Timer? _debounce;

  static const Duration _debounceDuration = Duration(milliseconds: 350);

  bool _loading = true;
  String? _error;
  List<KnowledgeItem> _items = const <KnowledgeItem>[];
  int _total = 0;

  /// 请求序号。网络返回顺序无法保证 —— 快速切换分类时，
  /// 先发的请求可能后返回，把新结果覆盖成旧结果。
  /// 只接受「最后一次请求」的返回值即可根除这个问题。
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    if (_ownsApi) _api.dispose();
    super.dispose();
  }

  /// 拉取列表。
  ///
  /// [showLoading] 为 false 时不显示整页加载态，
  /// 用于下拉刷新 —— 刷新时保留旧列表体验更好。
  Future<void> _load({bool showLoading = true}) async {
    final int requestId = ++_requestId;
    if (showLoading && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final PagedResult<KnowledgeItem> result = await _api.fetchKnowledge(
        categoryId: _selectedCategoryId,
        keyword: _keyword.isEmpty ? null : _keyword,
      );

      // 过期响应直接丢弃
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _loading = false;
        _error = null;
        _items = result.items;
        _total = result.total;
      });
    } on ApiException catch (error) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _loading = false;
        _error = error.message;
        _items = const <KnowledgeItem>[];
        _total = 0;
      });
    }
  }

  void _onKeywordChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(_debounceDuration, () {
      final String keyword = value.trim();
      if (keyword == _keyword) return;
      _keyword = keyword;
      _load();
    });
  }

  void _clearKeyword() {
    _debounce?.cancel();
    _searchController.clear();
    if (_keyword.isEmpty) return;
    _keyword = '';
    _load();
  }

  void _selectCategory(int? categoryId) {
    if (_selectedCategoryId == categoryId) return;
    setState(() => _selectedCategoryId = categoryId);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackgroundColor,
      appBar: AppBar(title: const Text('安全知识')),
      body: Column(
        children: <Widget>[
          // 搜索框
          Padding(
            padding: const EdgeInsets.fromLTRB(kPagePadding, 0, kPagePadding, 12),
            child: TextField(
              controller: _searchController,
              onChanged: _onKeywordChanged,
              onSubmitted: (String value) {
                _debounce?.cancel();
                final String keyword = value.trim();
                if (keyword == _keyword) return;
                _keyword = keyword;
                _load();
              },
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: '搜索安全知识',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                isDense: true,
                suffixIcon: _keyword.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: _clearKeyword,
                      ),
              ),
            ),
          ),

          // 分类筛选
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: kPagePadding),
              children: <Widget>[
                _CategoryChip(
                  // 分类名同时出现在筛选 chip 与知识卡片上，
                  // 加 key 便于测试精确定位到 chip 本身
                  key: const ValueKey<String>('category-chip-all'),
                  label: '全部',
                  selected: _selectedCategoryId == null,
                  color: Theme.of(context).colorScheme.primary,
                  onTap: () => _selectCategory(null),
                ),
                for (final SafetyCategory category in kCategories)
                  _CategoryChip(
                    key: ValueKey<String>('category-chip-${category.id}'),
                    label: category.name,
                    selected: _selectedCategoryId == category.id,
                    color: category.color,
                    onTap: () => _selectCategory(category.id),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const LoadingPlaceholder(message: '正在加载知识…');
    }

    if (_error != null) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(kPagePadding, 8, kPagePadding, 24),
        child: ErrorPlaceholder(
          message: _error!,
          hint: '知识内容来自后端服务，请确认后端已启动',
          onRetry: _load,
        ),
      );
    }

    if (_items.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _load(showLoading: false),
        child: ListView(
          // 让「空状态」也能下拉刷新：内容不足一屏时列表默认不可滚动
          physics: const AlwaysScrollableScrollPhysics(),
          children: <Widget>[
            const SizedBox(height: 60),
            EmptyPlaceholder(
              icon: Icons.menu_book_outlined,
              title: _keyword.isEmpty ? '暂无内容' : '没有找到相关知识',
              message: _keyword.isEmpty
                  ? '知识内容需经人工审核后才对外发布，\n审核完成前这里会保持为空。'
                  : '换个关键词或分类试试',
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _load(showLoading: false),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(kPagePadding, 0, kPagePadding, 24),
        // 共 N 条时最后一项用来显示条数，故 +1
        itemCount: _items.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: kCardGap),
        itemBuilder: (BuildContext context, int index) {
          if (index == _items.length) return _ResultCount(count: _total);
          return KnowledgeTile(
            item: _items[index],
            onTap: () => _openDetail(context, _items[index]),
          );
        },
      ),
    );
  }

  /// 知识详情页尚未实现（阶段 10）。
  /// 这里明确提示，而不是跳到一个空白页或假装已实现。
  void _openDetail(BuildContext context, KnowledgeItem item) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('「${item.title}」详情页将在阶段 10 实现'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

/// 列表底部的结果计数。
///
/// 显示的是服务端返回的 `total`（符合条件的总数），
/// 而不是本地列表长度 —— 分页之后两者并不相等。
class _ResultCount extends StatelessWidget {
  const _ResultCount({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Center(
        child: Text(
          '共 $count 条知识',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    super.key,
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: selected ? color.withValues(alpha: 0.12) : kSurfaceColor,
        borderRadius: BorderRadius.circular(19),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(19),
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(19),
              border: Border.all(
                color: selected
                    ? color.withValues(alpha: 0.5)
                    : const Color(0xFFE2E7EE),
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                color: selected ? color : const Color(0xFF5A6472),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
