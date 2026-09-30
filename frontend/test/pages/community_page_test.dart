import 'package:anzhi/core/auth_controller.dart';
import 'package:anzhi/pages/community_page.dart';
import 'package:anzhi/pages/post_compose_page.dart';
import 'package:anzhi/pages/post_detail_page.dart';
import 'package:anzhi/services/post_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_backend.dart';

/// 安知 —— 社区页测试（阶段 12a 列表，12c 点赞）
///
/// 重点：
///   · 三种「没有内容」必须分开说（加载中 / 拉不到 / 确实没人发帖）
///   · 点帖子进详情，回来后列表刷新
///   · 点赞只动那一条，不整页重刷
///   · 还没做的功能要**如实标注阶段**，而不是点了没反应
void main() {
  Future<void> pumpCommunity(
    WidgetTester tester,
    FakeBackend backend, {
    bool loggedIn = false,
  }) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final AuthController auth = backend.authController();
    if (loggedIn) {
      backend.seedAccount('xiaoming', 'hunter2hunter2');
      await auth.login(username: 'xiaoming', password: 'hunter2hunter2');
    }

    await tester.pumpWidget(
      AuthScope(
        controller: auth,
        child: MaterialApp(
          // 用 authController 的客户端：点赞要带上它的 token
          home: CommunityPage(api: PostApi(client: auth.apiClient)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('加载成功', () {
    testWidgets('列出后端返回的帖子', (WidgetTester tester) async {
      await pumpCommunity(tester, FakeBackend());

      expect(find.text('宿舍用电的几点提醒'), findsOneWidget);
      expect(find.text('遇到诈骗电话我是这么处理的'), findsOneWidget);
      expect(find.text('共 2 条帖子'), findsOneWidget);
    });

    testWidgets('每张卡片显示作者、摘要与互动数', (WidgetTester tester) async {
      await pumpCommunity(tester, FakeBackend());

      expect(find.text('小艾'), findsOneWidget);
      expect(find.text('不要在一个插排上同时接大功率电器。'), findsOneWidget);
      expect(find.text('3'), findsOneWidget, reason: '点赞数');
    });

    testWidgets('没有分类的帖子不画分类标签，但有分类的要画', (WidgetTester tester) async {
      await pumpCommunity(tester, FakeBackend());

      // 只有第一条有分类
      expect(find.text('用电安全'), findsOneWidget);
    });

    testWidgets('点帖子进详情页', (WidgetTester tester) async {
      await pumpCommunity(tester, FakeBackend());

      await tester.tap(find.text('宿舍用电的几点提醒'));
      await tester.pumpAndSettle();

      expect(find.byType(PostDetailPage), findsOneWidget);
    });

    testWidgets('点评论数也进详情页（评论区在那边）', (WidgetTester tester) async {
      await pumpCommunity(tester, FakeBackend());

      await tester.tap(find.byIcon(Icons.chat_bubble_outline_rounded).first);
      await tester.pumpAndSettle();

      expect(find.byType(PostDetailPage), findsOneWidget);
    });

    testWidgets('从详情页回来后列表会刷新', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend();
      await pumpCommunity(tester, backend);

      await tester.tap(find.text('宿舍用电的几点提醒'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.byType(CommunityPage), findsOneWidget);
      expect(find.text('共 2 条帖子'), findsOneWidget);
    });
  });

  group('点赞', () {
    testWidgets('未登录时提示登录，且不发请求', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend();

      await pumpCommunity(tester, backend);

      await tester.tap(find.byIcon(Icons.favorite_border_rounded).first);
      await tester.pumpAndSettle();

      expect(find.text('登录后可以点赞'), findsOneWidget);
      expect(
        backend.requests.where((Uri url) => url.path.endsWith('/like')).length,
        0,
        reason: '明知没登录还发一个注定 401 的请求，是白跑一趟',
      );
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('点一条只动那一条', (WidgetTester tester) async {
      await pumpCommunity(tester, FakeBackend(), loggedIn: true);

      await tester.tap(find.byIcon(Icons.favorite_border_rounded).first);
      await tester.pumpAndSettle();

      expect(find.text('4'), findsOneWidget, reason: '第一条 3 + 1');
      expect(
        find.text('5'),
        findsOneWidget,
        reason: '第二条没被点，数字不能跟着动',
      );
      expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
    });

    testWidgets('已经点过的帖子在列表里就是实心', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend()..seedLike('xiaoming', 2);

      await pumpCommunity(tester, backend, loggedIn: true);

      expect(
        find.byIcon(Icons.favorite_rounded),
        findsOneWidget,
        reason: '列表接口返回的 is_liked 要真的被用上',
      );
      expect(find.text('6'), findsOneWidget, reason: '第二条 5 + 1');
    });

    testWidgets('取消点赞后数字回落', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend()..seedLike('xiaoming', 1);

      await pumpCommunity(tester, backend, loggedIn: true);

      await tester.tap(find.byIcon(Icons.favorite_rounded));
      await tester.pumpAndSettle();

      expect(find.text('3'), findsOneWidget);
      expect(find.byIcon(Icons.favorite_rounded), findsNothing);
    });

    testWidgets('点赞失败时提示原因，数字不动', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend()..likeStatus = 500;

      await pumpCommunity(tester, backend, loggedIn: true);

      await tester.tap(find.byIcon(Icons.favorite_border_rounded).first);
      await tester.pumpAndSettle();

      expect(find.text('点赞失败，请稍后再试'), findsOneWidget);
      expect(
        find.text('3'),
        findsOneWidget,
        reason: '没成功就不能动数字 —— 那是骗用户',
      );
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('发帖入口', () {
    testWidgets('未登录时点发帖，提示登录而不是打开发帖页', (WidgetTester tester) async {
      await pumpCommunity(tester, FakeBackend());

      await tester.tap(find.text('发帖'));
      await tester.pumpAndSettle();

      expect(find.text('登录后可以发帖'), findsOneWidget);
      expect(find.byType(PostComposePage), findsNothing);
    });

    testWidgets('登录后点发帖打开发帖页', (WidgetTester tester) async {
      await pumpCommunity(tester, FakeBackend(), loggedIn: true);

      await tester.tap(find.text('发帖'));
      await tester.pumpAndSettle();

      expect(find.byType(PostComposePage), findsOneWidget);
    });
  });

  group('尚未实现的功能', () {
    testWidgets('点搜索提示后续版本', (WidgetTester tester) async {
      await pumpCommunity(tester, FakeBackend());

      await tester.tap(find.byIcon(Icons.search_rounded));
      await tester.pumpAndSettle();

      expect(find.textContaining('后续版本'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('没有内容时', () {
    testWidgets('确实没人发帖时说「还没有人发帖」', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend()..seedNoPosts();

      await pumpCommunity(tester, backend);

      expect(find.text('还没有人发帖'), findsOneWidget);
    });

    testWidgets('加载失败时给原因和重试按钮，而不是伪装成「还没人发帖」',
        (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend()
        ..errorStatus = 500
        ..errorBody = <String, dynamic>{'detail': '服务器内部错误'};

      await pumpCommunity(tester, backend);

      expect(find.text('服务器内部错误'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '重试'), findsOneWidget);
      expect(
        find.text('还没有人发帖'),
        findsNothing,
        reason: '拉不到和确实没有是两回事，不能混为一谈',
      );
    });

    testWidgets('重试成功后显示内容', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend()
        ..errorStatus = 500
        ..errorBody = <String, dynamic>{'detail': '服务器内部错误'};

      await pumpCommunity(tester, backend);
      expect(find.text('服务器内部错误'), findsOneWidget);

      // 后端恢复。errorStatus 为 null 就够了 —— 假后端只在它非空时才走错误分支。
      backend.errorStatus = null;

      await tester.tap(find.widgetWithText(OutlinedButton, '重试'));
      await tester.pumpAndSettle();

      expect(find.text('宿舍用电的几点提醒'), findsOneWidget);
      expect(find.text('服务器内部错误'), findsNothing);
    });
  });

  group('分页', () {
    testWidgets('还有更多时显示「加载更多」，点完就没', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend();
      // 默认 2 条，每页 20 —— 再造 25 条才会出现翻页
      for (int i = 0; i < 25; i++) {
        backend.seedPost(title: '帖子 $i');
      }

      await pumpCommunity(tester, backend);

      // 底部在视口外（ListView 是懒构建的，不滚过去就不会被创建）
      final Finder moreButton = find.widgetWithText(OutlinedButton, '加载更多');
      await tester.scrollUntilVisible(moreButton, 400);
      expect(moreButton, findsOneWidget);

      await tester.tap(moreButton);
      await tester.pumpAndSettle();

      // 27 条一次加载完，按钮消失，改成显示总数 ——
      // 与浏览历史页的底部保持一致
      expect(find.widgetWithText(OutlinedButton, '加载更多'), findsNothing);
      await tester.scrollUntilVisible(find.text('共 27 条帖子'), 400);
      expect(find.text('共 27 条帖子'), findsOneWidget);
    });
  });
}
