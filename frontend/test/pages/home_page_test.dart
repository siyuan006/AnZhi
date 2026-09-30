import 'package:anzhi/pages/home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_backend.dart';

/// 安知 —— 首页 Widget 测试（阶段 7）
///
/// 首页是「后端不可用时最不该整页崩掉」的页面：
/// 知识模块可以失败，但分类、AI 入口、社区仍应可用。
/// 首页内容长于默认测试窗口（800x600），下半部分会落在视口外而不被构建。
/// 放大窗口让整个首页参与布局，才能断言分类 / AI / 社区这些靠后的模块。
Future<void> useTallWindow(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(800, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

void main() {
  Widget wrap(FakeBackend backend, {List<int>? tabs}) => MaterialApp(
        home: HomePage(
          api: backend.api(),
          onNavigateToTab: tabs?.add,
        ),
      );

  group('加载成功', () {
    testWidgets('今日安全知识与推荐知识都来自后端', (WidgetTester tester) async {
      await useTallWindow(tester);
      final FakeBackend backend = FakeBackend();

      await tester.pumpWidget(wrap(backend));
      await tester.pumpAndSettle();

      expect(find.text('今日安全知识'), findsOneWidget);
      // 今日取第一条
      expect(find.text('宿舍发生火灾如何正确逃生'), findsOneWidget);
      // 推荐取其余条目
      expect(find.text('推荐知识'), findsOneWidget);
      expect(find.text('识别电信诈骗的五个通用信号'), findsOneWidget);
    });

    testWidgets('只取首页需要的少量数据，不拉整库', (WidgetTester tester) async {
      await useTallWindow(tester);
      final FakeBackend backend = FakeBackend();

      await tester.pumpWidget(wrap(backend));
      await tester.pumpAndSettle();

      final Uri sent = backend.requests.single;
      expect(int.parse(sent.queryParameters['page_size']!), lessThanOrEqualTo(10));
    });
  });

  group('内容为空', () {
    testWidgets('如实提示内容待审核，而不是显示假数据', (WidgetTester tester) async {
      await useTallWindow(tester);
      final FakeBackend backend = FakeBackend(items: <Map<String, dynamic>>[]);

      await tester.pumpWidget(wrap(backend));
      await tester.pumpAndSettle();

      expect(find.text('暂无知识内容'), findsOneWidget);
      expect(find.textContaining('人工审核'), findsOneWidget);
      // 占位数据已删除，界面不应再出现任何编造的知识标题
      expect(find.text('宿舍发生火灾如何正确逃生'), findsNothing);
    });

    testWidgets('知识为空不影响分类与 AI 入口', (WidgetTester tester) async {
      await useTallWindow(tester);
      final FakeBackend backend = FakeBackend(items: <Map<String, dynamic>>[]);

      await tester.pumpWidget(wrap(backend));
      await tester.pumpAndSettle();

      expect(find.text('安全分类'), findsOneWidget);
      expect(find.text('AI 安全助手'), findsOneWidget);
      expect(find.text('消防安全'), findsOneWidget);
    });
  });

  group('加载失败', () {
    testWidgets('后端连不上时给出提示，页面其余部分照常可用', (WidgetTester tester) async {
      await useTallWindow(tester);
      final FakeBackend backend = FakeBackend()..offline = true;

      await tester.pumpWidget(wrap(backend));
      await tester.pumpAndSettle();

      expect(find.textContaining('无法连接到服务器'), findsOneWidget);
      expect(find.text('AI 安全助手'), findsOneWidget);
      expect(find.text('安全分类'), findsOneWidget);
    });

    testWidgets('点击重试后能恢复成功', (WidgetTester tester) async {
      await useTallWindow(tester);
      final FakeBackend backend = FakeBackend()..offline = true;

      await tester.pumpWidget(wrap(backend));
      await tester.pumpAndSettle();

      backend.offline = false;
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();

      expect(find.text('今日安全知识'), findsOneWidget);
      expect(find.textContaining('无法连接到服务器'), findsNothing);
    });
  });

  group('跳转回调', () {
    testWidgets('点击 AI 入口回到指定标签', (WidgetTester tester) async {
      await useTallWindow(tester);
      final List<int> tabs = <int>[];
      final FakeBackend backend = FakeBackend();

      await tester.pumpWidget(wrap(backend, tabs: tabs));
      await tester.pumpAndSettle();

      // 示例问题 chip 才是可点击区域
      await tester.tap(find.text('宿舍发生火灾怎么办？'));
      await tester.pumpAndSettle();

      // AI 页在底部导航中的索引为 1
      expect(tabs, <int>[1]);
    });
  });
}
