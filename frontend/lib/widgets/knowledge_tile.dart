import 'package:flutter/material.dart';

import '../core/app_constants.dart';
import '../core/app_theme.dart';
import '../models/knowledge_item.dart';
import 'risk_badge.dart';

/// 安知 —— 知识卡片列表项
///
/// 用于首页推荐列表与知识列表页。点击后通过 [onTap] 交给调用方处理跳转，
/// 组件本身不感知路由，便于复用。
class KnowledgeTile extends StatelessWidget {
  const KnowledgeTile({
    super.key,
    required this.item,
    this.onTap,
    this.showSummary = true,
  });

  final KnowledgeItem item;
  final VoidCallback? onTap;

  /// 是否显示简介。紧凑列表可关闭
  final bool showSummary;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final SafetyCategory? category = item.category;

    return Material(
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
              // 分类 + 风险等级
              Row(
                children: <Widget>[
                  Expanded(
                    child: category == null
                        ? const SizedBox.shrink()
                        : Row(
                            children: <Widget>[
                              Icon(category.icon,
                                  size: 14, color: category.color),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  category.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: category.color,
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),
                  const SizedBox(width: 8),
                  RiskBadge(level: item.riskLevel, compact: true),
                ],
              ),
              const SizedBox(height: 9),

              // 标题
              Text(
                item.title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  height: 1.35,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),

              // 简介
              if (showSummary && item.summary.isNotEmpty) ...<Widget>[
                const SizedBox(height: 6),
                Text(
                  item.summary,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],

              // 浏览量
              if (item.viewCount > 0) ...<Widget>[
                const SizedBox(height: 9),
                Row(
                  children: <Widget>[
                    Icon(
                      Icons.remove_red_eye_outlined,
                      size: 13,
                      color: theme.colorScheme.outline,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '${item.viewCount}',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
