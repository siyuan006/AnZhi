import 'package:flutter/material.dart';

import '../core/app_constants.dart';
import '../core/app_theme.dart';
import '../core/sample_data.dart';
import '../models/knowledge_item.dart';
import '../models/paged_result.dart';
import '../services/api_client.dart';
import '../services/knowledge_api.dart';
import '../widgets/async_status.dart';
import '../widgets/category_grid.dart';
import '../widgets/knowledge_tile.dart';
import '../widgets/risk_badge.dart';
import '../widgets/section_header.dart';
import 'knowledge_detail_page.dart';

/// 安知 —— 首页
///
/// 模块顺序严格遵循 PROJECT_SPEC.md 第七节：
///   顶部 → 今日安全知识 → 推荐知识卡片 → 安全分类 → AI 助手入口 → 社区精选
///
/// 数据来源（阶段 7 起）：
///   - 今日安全知识 / 推荐知识：`GET /api/knowledge`（取最新 5 条）
///   - 安全分类：本地常量 `kCategories`，与数据库种子数据一致
///     （图标与配色无法由 JSON 表达，故保留在客户端）
///   - 社区精选：仍为占位数据，社区接口属阶段 12
///
/// ⚠️ 尚未实现：`GET /api/home` 聚合接口（docs/API.md 第 9 节）。
/// 该接口能减少客户端请求数，但属于优化项而非阶段 7 的必需项，
/// 因此暂由本页直接调用知识列表接口，待阶段 13（个性化）一并实现。
class HomePage extends StatefulWidget {
  const HomePage({super.key, this.onNavigateToTab, this.api});

  /// 请求切换到其他底部标签（如点击 AI 入口跳到 AI 页）
  final void Function(int index)? onNavigateToTab;

  /// 允许注入，便于测试用假客户端替换真实网络
  final KnowledgeApi? api;

  /// 底部导航索引：AI = 1，知识 = 2，社区 = 3
  static const int _tabAi = 1;
  static const int _tabKnowledge = 2;
  static const int _tabCommunity = 3;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final KnowledgeApi _api = widget.api ?? KnowledgeApi();
  late final bool _ownsApi = widget.api == null;

  /// 首页只需要「今日 1 条 + 推荐 4 条」，多取一条留出余量
  static const int _fetchSize = 5;

  bool _loading = true;
  String? _error;
  List<KnowledgeItem> _items = const <KnowledgeItem>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    if (_ownsApi) _api.dispose();
    super.dispose();
  }

  void _goTo(int index) => widget.onNavigateToTab?.call(index);

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final PagedResult<KnowledgeItem> result =
          await _api.fetchKnowledge(pageSize: _fetchSize);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = null;
        _items = result.items;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.message;
        _items = const <KnowledgeItem>[];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackgroundColor,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              kPagePadding,
              8,
              kPagePadding,
              24,
            ),
            children: <Widget>[
              const _HomeHeader(),
              const SizedBox(height: 18),

              // ① 今日安全知识 + ② 推荐知识
              ..._buildKnowledgeSections(),
              const SizedBox(height: 22),

              // ③ 安全分类
              SectionHeader(
                title: '安全分类',
                subtitle: '六大领域，系统学习',
                icon: Icons.grid_view_rounded,
                actionLabel: '全部',
                onAction: () => _goTo(HomePage._tabKnowledge),
              ),
              CategoryGrid(
                onCategoryTap: (_) => _goTo(HomePage._tabKnowledge),
              ),
              const SizedBox(height: 22),

              // ④ AI 助手入口
              _AiEntryCard(onTap: () => _goTo(HomePage._tabAi)),
              const SizedBox(height: 22),

              // ⑤ 社区精选
              SectionHeader(
                title: '社区精选',
                subtitle: '看看大家在讨论什么',
                icon: Icons.forum_outlined,
                actionLabel: '进入社区',
                onAction: () => _goTo(HomePage._tabCommunity),
              ),
              _CommunityPreview(
                posts: kSampleFeaturedPosts,
                onTap: () => _goTo(HomePage._tabCommunity),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// ① 今日安全知识 + ② 推荐知识
  ///
  /// 三种状态分开渲染：加载中、加载失败（可重试）、后端暂无已发布内容。
  /// 失败时只影响这两块，分类 / AI 入口 / 社区仍可正常使用。
  List<Widget> _buildKnowledgeSections() {
    if (_loading) {
      return const <Widget>[LoadingPlaceholder(message: '正在加载今日安全知识…')];
    }

    if (_error != null) {
      return <Widget>[
        ErrorPlaceholder(
          message: _error!,
          hint: '首页内容来自后端服务，请确认后端已启动',
          onRetry: _load,
        ),
      ];
    }

    if (_items.isEmpty) {
      return const <Widget>[
        EmptyPlaceholder(
          icon: Icons.menu_book_outlined,
          title: '暂无知识内容',
          message: '知识内容需经人工审核后才对外发布，\n审核完成前首页会保持为空。',
        ),
      ];
    }

    final List<KnowledgeItem> recommended =
        _items.length > 1 ? _items.sublist(1) : _items;

    return <Widget>[
      _DailyKnowledgeCard(
        item: _items.first,
        // 首页卡片直接把条目带过去，详情页不必再从列表里找一遍
        onTap: () => _openDetail(_items.first),
      ),
      const SizedBox(height: 22),
      SectionHeader(
        title: '推荐知识',
        subtitle: '根据你的关注方向推荐',
        icon: Icons.recommend_outlined,
        actionLabel: '更多',
        onAction: () => _goTo(HomePage._tabKnowledge),
      ),
      _RecommendList(
        items: recommended,
        onTap: (KnowledgeItem item) => _openDetail(item),
      ),
    ];
  }

  void _openDetail(KnowledgeItem item) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => KnowledgeDetailPage(
          knowledgeId: item.id,
          preview: item,
          api: widget.api,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 顶部
// ---------------------------------------------------------------------------

class _HomeHeader extends StatelessWidget {
  const _HomeHeader();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Row(
      children: <Widget>[
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.shield_moon_outlined,
            color: Colors.white,
            size: 24,
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                kAppName,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: 22,
                ),
              ),
              Text(
                kAppSlogan,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () {},
          icon: const Icon(Icons.notifications_none_rounded),
          tooltip: '通知',
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// ① 今日安全知识
// ---------------------------------------------------------------------------

class _DailyKnowledgeCard extends StatelessWidget {
  const _DailyKnowledgeCard({required this.item, this.onTap});

  final KnowledgeItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Material(
      borderRadius: BorderRadius.circular(16),
      color: theme.colorScheme.primary,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Icon(
                    Icons.wb_sunny_outlined,
                    size: 16,
                    color: Colors.white70,
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    '今日安全知识',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.white70,
                    ),
                  ),
                  const Spacer(),
                  RiskBadge(level: item.riskLevel, compact: true),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                item.title,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  height: 1.35,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Text(
                item.summary,
                style: const TextStyle(
                  fontSize: 13,
                  color: Colors.white70,
                  height: 1.55,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  Text(
                    '查看详情',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.white.withValues(alpha: 0.95),
                    ),
                  ),
                  const SizedBox(width: 3),
                  const Icon(
                    Icons.arrow_forward_rounded,
                    size: 15,
                    color: Colors.white,
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

// ---------------------------------------------------------------------------
// ② 推荐知识
// ---------------------------------------------------------------------------

class _RecommendList extends StatelessWidget {
  const _RecommendList({required this.items, this.onTap});

  final List<KnowledgeItem> items;

  /// 回调带上被点的那一条 —— 之前是无参的，只能「跳到知识页」，
  /// 现在要打开对应条目的详情，必须知道点的是谁。
  final void Function(KnowledgeItem item)? onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        for (int i = 0; i < items.length; i++) ...<Widget>[
          KnowledgeTile(
            item: items[i],
            onTap: onTap == null ? null : () => onTap!(items[i]),
          ),
          if (i != items.length - 1) const SizedBox(height: kCardGap),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// ④ AI 助手入口
// ---------------------------------------------------------------------------

class _AiEntryCard extends StatelessWidget {
  const _AiEntryCard({this.onTap});

  final VoidCallback? onTap;

  /// 示例问题：点击后应直接带入 AI 页面并提问。
  /// 目前仅作展示，接入 AI 页面后由回调传递。
  static const List<String> _examples = <String>[
    '宿舍发生火灾怎么办？',
    '电动车能在楼道充电吗？',
  ];

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: kSurfaceColor,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.auto_awesome,
                  size: 19,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'AI 安全助手',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      '有安全问题，随时问我',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final String q in _examples)
                ActionChip(
                  label: Text(q),
                  onPressed: onTap,
                  labelStyle: const TextStyle(fontSize: 12.5),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ⑤ 社区精选
// ---------------------------------------------------------------------------

/// ⚠️ 数据来源仍为 `core/sample_data.dart` 占位帖子。
/// 社区接口（`GET /api/posts`）属阶段 12，届时一并接真实数据。
class _CommunityPreview extends StatelessWidget {
  const _CommunityPreview({required this.posts, this.onTap});

  final List<SamplePost> posts;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      children: <Widget>[
        for (final SamplePost post in posts)
          Padding(
            padding: const EdgeInsets.only(bottom: kCardGap),
            child: Material(
              color: kSurfaceColor,
              borderRadius: BorderRadius.circular(kCardRadius),
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(kCardRadius),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        post.title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 14.5,
                          height: 1.4,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: <Widget>[
                          Icon(
                            Icons.person_outline_rounded,
                            size: 13,
                            color: theme.colorScheme.outline,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            post.author,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: theme.colorScheme.outline,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Icon(
                            Icons.favorite_border_rounded,
                            size: 13,
                            color: theme.colorScheme.outline,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '${post.likeCount}',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: theme.colorScheme.outline,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 13,
                            color: theme.colorScheme.outline,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '${post.commentCount}',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
