import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anzhi/app.dart';

import 'helpers/fake_backend.dart';

/// 安知 —— 应用级 Widget 测试
///
/// 阶段 3 / 4 的验收目标（PROJECT_SPEC 第三十节）：
///   启动 App → 显示安知首页 → 底部导航 → 5 个页面可以切换
///
/// 阶段 7 起首页与知识页要访问后端，因此这里的测试分两组：
///   - 注入假后端：验证真实数据能被渲染出来
///   - 不注入（测试环境天然无法访问网络）：验证 App 不崩溃、导航仍可用
void main() {
  group('应用启动与底部导航', () {
    testWidgets('启动后显示首页', (WidgetTester tester) async {
      await tester.pumpWidget(AnZhiApp(knowledgeApi: FakeBackend().api()));
      await tester.pumpAndSettle();

      // 首页顶部应出现应用名
      expect(find.text('安知'), findsOneWidget);
      // 首页第一个模块「今日安全知识」
      expect(find.text('今日安全知识'), findsOneWidget);
    });

    testWidgets('底部导航包含五个入口', (WidgetTester tester) async {
      await tester.pumpWidget(AnZhiApp(knowledgeApi: FakeBackend().api()));
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
      await tester.pumpWidget(AnZhiApp(knowledgeApi: FakeBackend().api()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('AI').last);
      await tester.pumpAndSettle();

      expect(find.text('AI 安全助手'), findsOneWidget);
    });

    testWidgets('可以切换到知识页面', (WidgetTester tester) async {
      await tester.pumpWidget(AnZhiApp(knowledgeApi: FakeBackend().api()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('知识').last);
      await tester.pumpAndSettle();

      expect(find.text('安全知识'), findsOneWidget);
    });

    testWidgets('可以切换到社区页面', (WidgetTester tester) async {
      await tester.pumpWidget(AnZhiApp(knowledgeApi: FakeBackend().api()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('社区').last);
      await tester.pumpAndSettle();

      expect(find.text('发帖'), findsOneWidget);
    });

    testWidgets('可以切换到我的页面', (WidgetTester tester) async {
      await tester.pumpWidget(AnZhiApp(knowledgeApi: FakeBackend().api()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('我的').last);
      await tester.pumpAndSettle();

      expect(find.text('关于安知'), findsOneWidget);
    });
  });

  group('后端不可用时的表现', () {
    testWidgets('没有后端也能启动并切换页面，不崩溃、不显示假数据', (WidgetTester tester) async {
      // 不注入假后端：flutter test 环境下所有 HTTP 请求都会失败，
      // 等价于「用户没开后端 / 手机没网」这一最常见场景
      await tester.pumpWidget(const AnZhiApp());
      await tester.pumpAndSettle();

      expect(find.text('安知'), findsOneWidget);

      // 首页知识模块如实报错（具体文案随失败原因而变，这里断言重试入口），
      // 但页面其余部分与导航栏仍然可用
      expect(find.text('重试'), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);
      // 不再显示任何编造的知识标题
      expect(find.text('宿舍发生火灾如何正确逃生'), findsNothing);

      // 切到知识页同样给出可读提示，而不是白屏
      await tester.tap(find.text('知识').last);
      await tester.pumpAndSettle();
      expect(find.text('安全知识'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
    });
  });

  group('前后端连通（假后端）', () {
    testWidgets('首页与知识页渲染的是接口返回的数据', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend();
      await tester.pumpWidget(AnZhiApp(knowledgeApi: backend.api()));
      await tester.pumpAndSettle();

      expect(find.text('宿舍发生火灾如何正确逃生'), findsOneWidget);

      await tester.tap(find.text('知识').last);
      await tester.pumpAndSettle();

      expect(find.text('共 2 条知识'), findsOneWidget);
      expect(find.text('识别电信诈骗的五个通用信号'), findsWidgets);
    });
  });
}
