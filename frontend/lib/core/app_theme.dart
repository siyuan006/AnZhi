import 'package:flutter/material.dart';

/// 安知 —— 应用主题
///
/// UI 原则（PROJECT_SPEC 第三十一节）：
///   简洁 · 现代 · 安全感 · 信息清晰 · 适合大学生
///
/// 配色思路：以可信赖的蓝色为主色调，配合大量留白与克制的阴影，
/// 传达「安全感」而不是「警告感」—— 风险色只在风险等级标签上出现。

/// 主色种子：沉稳的蓝
const Color kSeedColor = Color(0xFF1E6FD9);

/// 页面背景（浅灰，让白色卡片自然浮现）
const Color kBackgroundColor = Color(0xFFF5F7FA);

/// 卡片背景
const Color kSurfaceColor = Colors.white;

class AppTheme {
  const AppTheme._();

  /// 浅色主题
  static ThemeData get light {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: kSeedColor,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: kBackgroundColor,

      // 顶部栏：无阴影，与页面同色，干净
      appBarTheme: AppBarTheme(
        backgroundColor: kBackgroundColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
        iconTheme: IconThemeData(color: scheme.onSurface),
      ),

      // 卡片：白底、圆角、极轻阴影
      cardTheme: CardThemeData(
        color: kSurfaceColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),

      // 底部导航
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: kSurfaceColor,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer,
        elevation: 3,
        height: 64,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final bool selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
          );
        }),
      ),

      // 输入框
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: kSurfaceColor,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
      ),

      // 主按钮
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      dividerTheme: const DividerThemeData(
        color: Color(0xFFE8ECF1),
        thickness: 1,
        space: 1,
      ),

      chipTheme: ChipThemeData(
        backgroundColor: kSurfaceColor,
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        labelStyle: const TextStyle(fontSize: 13),
      ),
    );
  }
}
