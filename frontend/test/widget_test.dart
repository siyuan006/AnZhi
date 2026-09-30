import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anzhi/app.dart';

/// 安知 —— 基础 Widget 测试
///
/// 阶段 3 / 4 的验收目标（PROJECT_SPEC 第三十节）：
///   启动 App → 显示安知首页 → 底部导航 → 5 个页面可以切换
void main() {
  group('应用启动与底部导航', () {
    testWidgets('启动后显示首页', (WidgetTester tester) async {
      await tester.pumpWidget(const AnZhiApp());
      await tester.pumpAndSettle();

      // 首页顶部应出现应用名
      expect(find.text('安知'), findsOneWidget);
      // 首页第一个模块「今日安全知识」
      expect(find.text('今日安全知识'), findsOneWidget);
    });

    testWidgets('底部导航包含五个入口', (WidgetTester tester) async {
      await tester.pumpWidget(const AnZhiApp());
      await tester.pumpAndSettle();

      expect(find.byType(NavigationBar), findsOneWidget);

      for (final String label in <String>['首页', 'AI', '知识', '社区', '我的']) {
        expect(
          find.text(label),
          findsWidgets,
          reason: '底部导航缺少「$label」入口',
        );
      }
    });

    testWidgets('可以切换到 AI 页面', (WidgetTester tester) async {
      await tester.pumpWidget(const AnZhiApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('AI').last);
      await tester.pumpAndSettle();

      expect(find.text('AI 安全助手'), findsOneWidget);
    });

    testWidgets('可以切换到知识页面', (WidgetTester tester) async {
      await tester.pumpWidget(const AnZhiApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('知识').last);
      await tester.pumpAndSettle();

      expect(find.text('安全知识'), findsOneWidget);
    });

    testWidgets('可以切换到社区页面', (WidgetTester tester) async {
      await tester.pumpWidget(const AnZhiApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('社区').last);
      await tester.pumpAndSettle();

      expect(find.text('发帖'), findsOneWidget);
    });

    testWidgets('可以切换到我的页面', (WidgetTester tester) async {
      await tester.pumpWidget(const AnZhiApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('我的').last);
      await tester.pumpAndSettle();

      expect(find.text('关于安知'), findsOneWidget);
    });
  });
}
