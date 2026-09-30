import 'package:flutter/material.dart';

import '../core/app_constants.dart';
import '../core/app_theme.dart';
import '../core/sample_data.dart';
import '../models/knowledge_item.dart';
import '../widgets/category_grid.dart';
import '../widgets/knowledge_tile.dart';
import '../widgets/risk_badge.dart';
import '../widgets/section_header.dart';

/// 安知 —— 首页
///
/// 模块顺序严格遵循 PROJECT_SPEC.md 第七节：
///   顶部 → 今日安全知识 → 推荐知识卡片 → 安全分类 → AI 助手入口 → 社区精选
///
/// V1.0 暂不实现复杂推荐算法，使用「固定推荐 + 简单用户兴趣」（第七节）。
///
/// ⚠️ 当前数据来源为 `core/sample_data.dart` 占位数据，
/// 阶段 7「前后端通信」完成后改为调用 `GET /api/home`。
class HomePage extends StatelessWidget {
  const HomePage({super.key, this.onNavigateToTab});

  /// 请求切换到其他底部标签（如点击 AI 入口跳到 AI 页）
  final void Function(int index)? onNavigateToTab;

  /// 底部导航索引：AI = 1，知识 = 2，社区 = 3
  static const int _tabAi = 1;
  static const int _tabKnowledge = 2;
  static const int _tabCommunity = 3;

  void _goTo(int index) => onNavigateToTab?.call(index);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackgroundColor,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            kPagePadding,
            8,
            kPagePadding,
            24,
          ),
          children: <Widget>[
            const _HomeHeader(),
            const SizedBox(height: 18),

            // ① 今日安全知识
            _DailyKnowledgeCard(
              item: kSampleDailyKnowledge,
              onTap: () => _goTo(_tabKnowledge),
            ),
            const SizedBox(height: 22),

            // ② 推荐知识卡片
            SectionHeader(
              title: '推荐知识',
              subtitle: '根据你的关注方向推荐',
              icon: Icons.recommend_outlined,
              actionLabel: '更多',
              onAction: () => _goTo(_tabKnowledge),
            ),
            _RecommendList(
              items: kSampleRecommended,
              onTap: () => _goTo(_tabKnowledge),
            ),
            const SizedBox(height: 22),

            // ③ 安全分类
            SectionHeader(
              title: '安全分类',
              subtitle: '六大领域，系统学习',
              icon: Icons.grid_view_rounded,
              actionLabel: '全部',
              onAction: () => _goTo(_tabKnowledge),
            ),
            CategoryGrid(
              onCategoryTap: (_) => _goTo(_tabKnowledge),
            ),
            const SizedBox(height: 22),

            // ④ AI 助手入口
            _AiEntryCard(onTap: () => _goTo(_tabAi)),
            const SizedBox(height: 22),

            // ⑤ 社区精选
            SectionHeader(
              title: '社区精选',
              subtitle: '看看大家在讨论什么',
              icon: Icons.forum_outlined,
              actionLabel: '进入社区',
              onAction: () => _goTo(_tabCommunity),
            ),
            _CommunityPreview(
              posts: kSampleFeaturedPosts,
              onTap: () => _goTo(_tabCommunity),
            ),
          ],
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
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        for (int i = 0; i < items.length; i++) ...<Widget>[
          KnowledgeTile(item: items[i], onTap: onTap),
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
