import 'package:flutter/material.dart';

import '../core/app_theme.dart';

/// 安知 —— 网络请求的三种非正常状态占位
///
/// 阶段 7 起页面数据来自后端，于是必然出现三种「没有内容可渲染」的情况：
/// 加载中、加载失败、加载成功但结果为空。
///
/// 三者必须区分开。把「加载失败」显示成「暂无内容」是一种欺骗 ——
/// 用户会以为知识库是空的，而实际上是后端没启动。

/// 加载中
class LoadingPlaceholder extends StatelessWidget {
  const LoadingPlaceholder({super.key, this.message = '正在加载…'});

  final String message;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: <Widget>[
          const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
          const SizedBox(height: 14),
          Text(
            message,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// 加载失败：给原因，也给重试按钮
class ErrorPlaceholder extends StatelessWidget {
  const ErrorPlaceholder({
    super.key,
    required this.message,
    this.onRetry,
    this.hint,
  });

  /// 面向用户的失败原因（由 `ApiException.message` 提供）
  final String message;

  /// 附加建议，例如「确认后端已启动」
  final String? hint;

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      decoration: BoxDecoration(
        color: kSurfaceColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: <Widget>[
          Icon(
            Icons.cloud_off_rounded,
            size: 34,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 13.5,
              height: 1.5,
            ),
          ),
          if (hint != null) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              hint!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ],
          if (onRetry != null) ...<Widget>[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 17),
              label: const Text('重试'),
            ),
          ],
        ],
      ),
    );
  }
}

/// 加载成功但结果为空
class EmptyPlaceholder extends StatelessWidget {
  const EmptyPlaceholder({
    super.key,
    this.title = '暂无内容',
    this.message,
    this.icon = Icons.inbox_outlined,
  });

  final String title;
  final String? message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Column(
        children: <Widget>[
          Icon(icon, size: 32, color: theme.colorScheme.outline),
          const SizedBox(height: 12),
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          if (message != null) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
