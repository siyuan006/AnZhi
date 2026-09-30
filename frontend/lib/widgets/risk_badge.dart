import 'package:flutter/material.dart';

import '../core/app_constants.dart';

/// 安知 —— 风险等级标签
///
/// 三级风险系统的视觉呈现（PROJECT_SPEC 第十节）。
/// 风险色是全局唯一的「警示色」来源，其余界面保持中性，
/// 避免整屏都在喊「危险」反而削弱提示效果。
class RiskBadge extends StatelessWidget {
  const RiskBadge({
    super.key,
    required this.level,
    this.compact = false,
  });

  final RiskLevel level;

  /// 紧凑模式：仅图标 + 文字，用于列表项
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: level.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: level.color.withValues(alpha: 0.35),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(level.icon, size: compact ? 12 : 14, color: level.color),
          const SizedBox(width: 4),
          Text(
            level.label,
            style: TextStyle(
              fontSize: compact ? 11 : 12,
              fontWeight: FontWeight.w600,
              color: level.color,
            ),
          ),
        ],
      ),
    );
  }
}
