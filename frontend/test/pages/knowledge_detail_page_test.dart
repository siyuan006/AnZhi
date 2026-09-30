import 'package:anzhi/models/knowledge_item.dart';
import 'package:anzhi/pages/knowledge_detail_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_backend.dart';

/// 安知 —— 知识详情页测试（阶段 10）
///
/// 两条容易做错、也最容易骗过自己的地方：
///  · 加载失败时必须说「加载失败」，不能显示成「暂无内容」
///  · 浏览计数是写操作，只在真正拿到正文之后才该发生
void main() {
  Future<void> useTallWindow(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  /// 列表页点进来时带的那一条（只有摘要，没有正文）
  KnowledgeItem preview({
    int id = 1,
    String title = '宿舍发生火灾如何正确逃生',
    String summary = '低姿撤离、不乘电梯、不贪恋财物。',
  }) {
    return KnowledgeItem(
      id: id,
      title: title,
      categoryId: 1,
      summary: summary,
    );
  }

  Future<void> pumpDetail(
    WidgetTester tester,
    FakeBackend backend, {
    KnowledgeItem? item,
    int id = 1,
  }) async {
    await useTallWindow(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: KnowledgeDetailPage(
          knowledgeId: id,
          preview: item,
          api: backend.api(),
        ),
      ),
    );
  }

  group('加载', () {
    testWidgets('展示标题、摘要与正文', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend();
      await pumpDetail(tester, backend, item: preview());
      await tester.pumpAndSettle();

      expect(find.text('宿舍发生火灾如何正确逃生'), findsOneWidget);
      expect(find.text('低姿撤离、不乘电梯、不贪恋财物。'), findsOneWidget);
      expect(find.text('正文内容，长度足够用于测试。'), findsOneWidget);
      // 分类与风险等级来自列表项/详情，都应出现
      expect(find.text('消防安全'), findsOneWidget);
      expect(find.text('高风险'), findsOneWidget);
    });

    testWidgets('正文没回来之前先显示列表页带过来的标题', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend()
        ..delay = const Duration(milliseconds: 300);
      await pumpDetail(tester, backend, item: preview());
      await tester.pump();

      // 用户点进来立刻看到自己点的那一条，而不是整页转圈
      expect(find.text('宿舍发生火灾如何正确逃生'), findsOneWidget);
      expect(find.text('正在加载正文…'), findsOneWidget);
      expect(find.text('正文内容，长度足够用于测试。'), findsNothing);

      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text('正文内容，长度足够用于测试。'), findsOneWidget);

      // 假后端的延迟对所有请求生效，计数的 POST 是拿到正文之后才发的，
      // 它自己的延迟计时器要再推一次才会结束 —— 否则测试结束时
      // 会留下一个未完成的 Timer 而报错。
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
    });

    testWidgets('没有带列表项时也不崩溃', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend();
      await pumpDetail(tester, backend, id: 1);
      await tester.pumpAndSettle();

      expect(find.text('宿舍发生火灾如何正确逃生'), findsOneWidget);
    });

    testWidgets('知识卡片也带安全提示', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend();
      await pumpDetail(tester, backend, item: preview());
      await tester.pumpAndSettle();

      // 用户可能只看卡片、不问 AI，所以卡片同样要有求助指引
      expect(find.textContaining('119'), findsOneWidget);
    });
  });

  group('失败', () {
    testWidgets('内容不存在时说明原因，而不是显示成空内容', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend();
      await pumpDetail(tester, backend, item: preview(), id: 999);
      await tester.pumpAndSettle();

      expect(find.text('知识不存在或未发布'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      // 关键：不能把「加载失败」显示成「这条没有正文」
      expect(find.text('这条内容暂时没有正文。'), findsNothing);
    });

    testWidgets('连不上后端时给出可读提示', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend()..offline = true;
      await pumpDetail(tester, backend, item: preview());
      await tester.pumpAndSettle();

      expect(find.textContaining('无法连接到服务器'), findsOneWidget);
    });

    testWidgets('重试成功后能正常显示', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend()..offline = true;
      await pumpDetail(tester, backend, item: preview());
      await tester.pumpAndSettle();

      backend.offline = false;
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();

      expect(find.text('正文内容，长度足够用于测试。'), findsOneWidget);
    });

    testWidgets('正文为空时如实说明，不留一片空白', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend(
        items: <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 1,
            'title': '只有标题',
            'category_id': 1,
            'content': '',
          },
        ],
      );
      await pumpDetail(tester, backend, item: preview(), id: 1);
      await tester.pumpAndSettle();

      // 什么都不说会让人以为「还没加载出来」，必须说明是「没有正文」
      expect(find.text('这条内容暂时没有正文。'), findsOneWidget);
      expect(find.text('正文内容，长度足够用于测试。'), findsNothing);
      // 但页面本身仍然是正常的，不是错误页
      expect(find.text('重试'), findsNothing);
    });
  });

  group('浏览计数', () {
    testWidgets('打开详情后记一次浏览并显示出来', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend();
      await pumpDetail(tester, backend, item: preview());
      await tester.pumpAndSettle();

      expect(backend.viewCounts[1], 1);
      expect(find.text('1 次浏览'), findsOneWidget);
    });

    testWidgets('计数请求发在 GET 详情之后', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend();
      await pumpDetail(tester, backend, item: preview());
      await tester.pumpAndSettle();

      // 先读到正文，再计数 —— 顺序反了会在内容不存在时也算一次
      final List<String> paths =
          backend.requests.map((Uri uri) => uri.path).toList();
      expect(paths, <String>['/api/knowledge/1', '/api/knowledge/1/view']);
    });

    testWidgets('加载失败时不计数', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend();
      await pumpDetail(tester, backend, item: preview(), id: 999);
      await tester.pumpAndSettle();

      expect(backend.viewCounts, isEmpty);
      expect(
        backend.requests.any((Uri uri) => uri.path.endsWith('/view')),
        isFalse,
      );
    });

    testWidgets('计数失败不影响正文显示', (WidgetTester tester) async {
      // 浏览量是锦上添花的数据，不该把一次正常的阅读变成错误页
      final FakeBackend backend = FakeBackend();
      await pumpDetail(tester, backend, item: preview());
      await tester.pumpAndSettle();

      expect(find.text('正文内容，长度足够用于测试。'), findsOneWidget);
    });
  });
}
