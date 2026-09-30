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
          // 社区精选也接上假后端。不注入的话它会去发真实请求，
          // 而 flutter_test 会拦掉 —— 那样测到的是失败分支，
          // 不是我们想验的那一条。
          postApi: backend.postApi(),
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

      // 阶段 12a 起首页会发两条请求（知识 + 社区精选），
      // 因此这里要挑出知识那条，而不是拿 requests.single
      final Uri sent = backend.requests
          .firstWhere((Uri url) => url.path == '/api/knowledge');
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

  group('社区精选（阶段 12a 接真实数据）', () {
    testWidgets('显示后端返回的帖子', (WidgetTester tester) async {
      await useTallWindow(tester);

      await tester.pumpWidget(wrap(FakeBackend()));
      await tester.pumpAndSettle();

      expect(find.text('社区精选'), findsOneWidget);
      expect(find.text('宿舍用电的几点提醒'), findsOneWidget);
      expect(find.text('小艾'), findsOneWidget);
    });

    testWidgets('还没人发帖时如实说明', (WidgetTester tester) async {
      await useTallWindow(tester);
      final FakeBackend backend = FakeBackend()..seedNoPosts();

      await tester.pumpWidget(wrap(backend));
      await tester.pumpAndSettle();

      expect(find.textContaining('还没有人发帖'), findsOneWidget);
    });

    testWidgets('社区拉不到时只说这一块，首页其余部分照常', (WidgetTester tester) async {
      // 知识才是首页的主体。社区精选是末尾的一小块 ——
      // 让它把整页变成错误页是本末倒置。
      await useTallWindow(tester);
      final FakeBackend backend = FakeBackend();

      await tester.pumpWidget(
        MaterialApp(
          home: HomePage(
            api: backend.api(),
            // 一个永远连不上的社区接口
            postApi: (FakeBackend()..offline = true).postApi(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('社区内容暂时加载不出来'), findsOneWidget);
      // 关键：不能滑成「还没有人发帖」——那是骗人
      expect(find.textContaining('还没有人发帖'), findsNothing);
      // 知识部分不受影响
      expect(find.text('今日安全知识'), findsOneWidget);
    });
  });
}
