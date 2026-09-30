import 'package:flutter/material.dart';

import '../core/app_constants.dart';
import '../core/app_theme.dart';

/// 安知 —— 安全分类网格
///
/// 六大分类的入口（PROJECT_SPEC 第四节）。
/// 3 列布局，每个分类用各自的主题色区分，便于快速识别。
class CategoryGrid extends StatelessWidget {
  const CategoryGrid({
    super.key,
    this.onCategoryTap,
    this.categories,
  });

  final void Function(SafetyCategory category)? onCategoryTap;

  /// 允许外部传入自定义分类列表，默认为全局六大分类
  final List<SafetyCategory>? categories;

  static const double _verticalPadding = 10;
  static const double _iconBoxSize = 38;
  static const double _iconGap = 8;
  static const double _labelFontSize = 12.5;
  static const double _labelHeightFactor = 1.25;
  static const int _labelMaxLines = 2;

  @override
  Widget build(BuildContext context) {
    final List<SafetyCategory> items = categories ?? kCategories;

    final double lineHeight = (MediaQuery.textScalerOf(context)
                .scale(_labelFontSize) *
            _labelHeightFactor)
        .ceilToDouble();
    final double labelHeight = lineHeight * _labelMaxLines;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        mainAxisExtent: _verticalPadding * 2 +
            _iconBoxSize +
            _iconGap +
            labelHeight,
      ),
      itemBuilder: (BuildContext context, int index) {
        final SafetyCategory category = items[index];
        return _CategoryCard(
          category: category,
          onTap: onCategoryTap == null ? null : () => onCategoryTap!(category),
        );
      },
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.category, this.onTap});

  final SafetyCategory category;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kSurfaceColor,
      borderRadius: BorderRadius.circular(kCardRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(kCardRadius),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 6,
            vertical: CategoryGrid._verticalPadding,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Container(
                width: CategoryGrid._iconBoxSize,
                height: CategoryGrid._iconBoxSize,
                decoration: BoxDecoration(
                  color: category.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(category.icon, size: 21, color: category.color),
              ),
              const SizedBox(height: CategoryGrid._iconGap),
              Text(
                category.name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: CategoryGrid._labelFontSize,
                  fontWeight: FontWeight.w600,
                  height: CategoryGrid._labelHeightFactor,
                ),
                maxLines: CategoryGrid._labelMaxLines,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
