import 'package:flutter/material.dart';

import '../core/app_constants.dart';
import '../core/app_theme.dart';
import '../core/sample_data.dart';
import '../models/knowledge_item.dart';
import '../widgets/knowledge_tile.dart';

/// 安知 —— 知识页
///
/// 结构（PROJECT_SPEC 第三十八节）：分类列表 → 知识列表 → 知识详情。
/// 本页承担前两级：顶部分类筛选 + 知识列表；详情页将在阶段 10 实现。
///
/// ⚠️ 当前数据来源为 `core/sample_data.dart` 占位数据，
/// 阶段 7 后改为调用 `GET /api/knowledge?category_id=...`。
class KnowledgePage extends StatefulWidget {
  const KnowledgePage({super.key});

  @override
  State<KnowledgePage> createState() => _KnowledgePageState();
}

class _KnowledgePageState extends State<KnowledgePage> {
  /// 当前选中的分类 id；`null` 表示「全部」
  int? _selectedCategoryId;

  final TextEditingController _searchController = TextEditingController();
  String _keyword = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// 按当前筛选条件过滤列表。
  ///
  /// 后端接通后这段过滤逻辑会下沉到服务端（`keyword` / `category_id` 查询参数），
  /// 客户端只负责渲染返回结果。
  List<KnowledgeItem> get _filtered {
    return kSampleKnowledge.where((KnowledgeItem item) {
      final bool matchCategory =
          _selectedCategoryId == null || item.categoryId == _selectedCategoryId;
      final bool matchKeyword = _keyword.isEmpty ||
          item.title.contains(_keyword) ||
          item.summary.contains(_keyword);
      return matchCategory && matchKeyword;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final List<KnowledgeItem> items = _filtered;

    return Scaffold(
      backgroundColor: kBackgroundColor,
      appBar: AppBar(title: const Text('安全知识')),
      body: Column(
        children: <Widget>[
          // 搜索框
          Padding(
            padding: const EdgeInsets.fromLTRB(
              kPagePadding,
              0,
              kPagePadding,
              12,
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (String value) =>
                  setState(() => _keyword = value.trim()),
              decoration: InputDecoration(
                hintText: '搜索安全知识',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                isDense: true,
                suffixIcon: _keyword.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _keyword = '');
                        },
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
                  label: '全部',
                  selected: _selectedCategoryId == null,
                  color: Theme.of(context).colorScheme.primary,
                  onTap: () => setState(() => _selectedCategoryId = null),
                ),
                for (final SafetyCategory category in kCategories)
                  _CategoryChip(
                    label: category.name,
                    selected: _selectedCategoryId == category.id,
                    color: category.color,
                    onTap: () =>
                        setState(() => _selectedCategoryId = category.id),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // 知识列表
          Expanded(
            child: items.isEmpty
                ? const _EmptyResult()
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(
                      kPagePadding,
                      0,
                      kPagePadding,
                      24,
                    ),
                    itemCount: items.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: kCardGap),
                    itemBuilder: (BuildContext context, int index) {
                      return KnowledgeTile(
                        item: items[index],
                        onTap: () => _openDetail(context, items[index]),
                      );
                    },
                  ),
          ),
        ],
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

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
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

class _EmptyResult extends StatelessWidget {
  const _EmptyResult();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.search_off_rounded,
            size: 44,
            color: theme.colorScheme.outlineVariant,
          ),
          const SizedBox(height: 12),
          Text(
            '没有找到相关知识',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '换个关键词或分类试试',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}
