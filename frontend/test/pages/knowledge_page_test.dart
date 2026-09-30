import 'package:anzhi/pages/knowledge_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_backend.dart';

/// 安知 —— 知识页 Widget 测试（阶段 7）
///
/// 阶段 7 的验收目标：Flutter 能把后端返回的数据渲染出来，
/// 并且在**后端不可用 / 无已发布内容**这两种真实情况下给出正确反馈。
void main() {
  Widget wrap(FakeBackend backend) => MaterialApp(
        home: KnowledgePage(api: backend.api()),
      );

  group('加载成功', () {
    testWidgets('渲染后端返回的知识条目', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend();

      await tester.pumpWidget(wrap(backend));
      await tester.pumpAndSettle();

      expect(find.text('宿舍发生火灾如何正确逃生'), findsOneWidget);
      expect(find.text('识别电信诈骗的五个通用信号'), findsOneWidget);
      // 条数来自服务端 total，而不是本地列表长度
      expect(find.text('共 2 条知识'), findsOneWidget);
    });

    testWidgets('加载过程中先显示加载态', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend()
        ..delay = const Duration(milliseconds: 200);

      await tester.pumpWidget(wrap(backend));
      await tester.pump(); // 只推进一帧，请求尚未返回

      expect(find.text('正在加载知识…'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(find.text('正在加载知识…'), findsNothing);
    });
  });

  group('空结果', () {
    testWidgets('后端无已发布内容时如实显示空状态，并说明原因', (WidgetTester tester) async {
      // 这不是假设：当前数据库 12 条初稿全部待审核，接口确实返回空
      final FakeBackend backend = FakeBackend(items: <Map<String, dynamic>>[]);

      await tester.pumpWidget(wrap(backend));
      await tester.pumpAndSettle();

      expect(find.text('暂无内容'), findsOneWidget);
      expect(find.textContaining('人工审核'), findsOneWidget);
      // 空状态不能被误报成「加载失败」
      expect(find.text('重试'), findsNothing);
    });
  });

  group('加载失败', () {
    testWidgets('后端连不上时给出提示和重试入口', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend()..offline = true;

      await tester.pumpWidget(wrap(backend));
      await tester.pumpAndSettle();

      expect(find.textContaining('无法连接到服务器'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
    });

    testWidgets('点击重试后能恢复成功', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend()..offline = true;

      await tester.pumpWidget(wrap(backend));
      await tester.pumpAndSettle();
      expect(find.text('重试'), findsOneWidget);

      // 后端恢复
      backend.offline = false;
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();

      expect(find.textContaining('无法连接到服务器'), findsNothing);
      expect(find.text('宿舍发生火灾如何正确逃生'), findsOneWidget);
    });
  });

  group('筛选下沉到服务端', () {
    testWidgets('点击分类后请求带上 category_id', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend();

      await tester.pumpWidget(wrap(backend));
      await tester.pumpAndSettle();
      backend.requests.clear();

      await tester.tap(find.byKey(const ValueKey<String>('category-chip-5')));
      await tester.pumpAndSettle();

      expect(backend.requests.single.queryParameters['category_id'], '5');
      // 客户端只渲染返回值：消防那条已被服务端筛掉
      expect(find.text('识别电信诈骗的五个通用信号'), findsOneWidget);
      expect(find.text('宿舍发生火灾如何正确逃生'), findsNothing);
    });

    testWidgets('再点「全部」会去掉分类参数', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend();

      await tester.pumpWidget(wrap(backend));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey<String>('category-chip-5')));
      await tester.pumpAndSettle();
      backend.requests.clear();

      await tester.tap(find.byKey(const ValueKey<String>('category-chip-all')));
      await tester.pumpAndSettle();

      expect(
        backend.requests.single.queryParameters.containsKey('category_id'),
        isFalse,
      );
      expect(find.text('共 2 条知识'), findsOneWidget);
    });

    testWidgets('输入关键词后（防抖结束）请求带上 keyword', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend();

      await tester.pumpWidget(wrap(backend));
      await tester.pumpAndSettle();
      backend.requests.clear();

      await tester.enterText(find.byType(TextField), '诈骗');
      // 防抖期内不应发起请求
      await tester.pump(const Duration(milliseconds: 100));
      expect(backend.requests, isEmpty);

      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(backend.requests.single.queryParameters['keyword'], '诈骗');
      expect(find.text('识别电信诈骗的五个通用信号'), findsOneWidget);
      expect(find.text('宿舍发生火灾如何正确逃生'), findsNothing);
    });

    testWidgets('搜索无结果时提示换个关键词', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend();

      await tester.pumpWidget(wrap(backend));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '不存在的关键词');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(find.text('没有找到相关知识'), findsOneWidget);
    });
  });
}
