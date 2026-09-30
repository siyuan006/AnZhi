import 'package:anzhi/core/auth_controller.dart';
import 'package:anzhi/pages/knowledge_detail_page.dart';
import 'package:anzhi/pages/login_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_backend.dart';

/// 安知 —— 知识详情页的收藏按钮（阶段 11b）
///
/// 这个按钮最容易做错的三件事：
///   · 正文还没到就先画一个「未收藏」—— 那是个可能错的答案
///   · 请求失败却把图标翻过去 —— 用户以为收藏成功了
///   · 未登录时只弹一句「请先登录」就没了
void main() {
  Future<AuthController> pumpDetail(
    WidgetTester tester,
    FakeBackend backend, {
    int knowledgeId = 1,
    AuthController? controller,
  }) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final AuthController auth = controller ?? backend.authController();
    await tester.pumpWidget(
      AuthScope(
        controller: auth,
        child: MaterialApp(
          home: KnowledgeDetailPage(knowledgeId: knowledgeId),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return auth;
  }

  Finder favoriteButton() => find.byTooltip('收藏');
  Finder unfavoriteButton() => find.byTooltip('取消收藏');

  group('未登录', () {
    testWidgets('照常显示正文，收藏按钮显示为未收藏', (WidgetTester tester) async {
      // 安知是安全科普应用：不登录也必须能读到内容
      await pumpDetail(tester, FakeBackend());

      expect(find.text('宿舍发生火灾如何正确逃生'), findsWidgets);
      expect(favoriteButton(), findsOneWidget);
      expect(unfavoriteButton(), findsNothing);
    });

    testWidgets('点收藏会打开登录页，而不是只弹一句提示', (WidgetTester tester) async {
      await pumpDetail(tester, FakeBackend());

      await tester.tap(favoriteButton());
      await tester.pumpAndSettle();

      expect(find.byType(LoginPage), findsOneWidget);
    });

    testWidgets('登录成功后自动把这次收藏做完，不用再点一次', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend()
        ..seedAccount('xiaoming', 'hunter2hunter2');
      final AuthController auth = await pumpDetail(tester, backend);

      await tester.tap(favoriteButton());
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, '用户名'), 'xiaoming');
      await tester.enterText(
        find.widgetWithText(TextField, '密码'),
        'hunter2hunter2',
      );
      await tester.tap(find.widgetWithText(FilledButton, '登录'));
      await tester.pumpAndSettle();

      expect(auth.isLoggedIn, isTrue);
      expect(find.byType(LoginPage), findsNothing);
      expect(backend.favorites['xiaoming'], <int>[1], reason: '他点的是收藏，登录只是路上的一步');
      expect(unfavoriteButton(), findsOneWidget);
    });

    testWidgets('登录后回到详情页，正文还在', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend()
        ..seedAccount('xiaoming', 'hunter2hunter2');
      await pumpDetail(tester, backend);

      await tester.tap(favoriteButton());
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.byType(KnowledgeDetailPage), findsOneWidget);
      expect(find.text('宿舍发生火灾如何正确逃生'), findsWidgets);
    });
  });

  group('已登录', () {
    Future<AuthController> pumpLoggedIn(
      WidgetTester tester,
      FakeBackend backend, {
      int knowledgeId = 1,
    }) async {
      final AuthController auth = backend.authController();
      await auth.login(username: 'xiaoming', password: 'hunter2hunter2');
      return pumpDetail(tester, backend, controller: auth, knowledgeId: knowledgeId);
    }

    testWidgets('已经收藏过的条目进来就是点亮状态', (WidgetTester tester) async {
      // 「这条我收过没有」必须按人算。直接查「有没有任何人收藏过」
      // 是很容易写错的一版，会让别人的收藏点亮你的按钮。
      final FakeBackend backend = FakeBackend()
        ..seedAccount('xiaoming', 'hunter2hunter2')
        ..seedFavorite('xiaoming', 1);

      await pumpLoggedIn(tester, backend);

      expect(unfavoriteButton(), findsOneWidget);
      expect(favoriteButton(), findsNothing);
    });

    testWidgets('别人的收藏不会点亮我的按钮', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend()
        ..seedAccount('xiaoming', 'hunter2hunter2')
        ..seedAccount('mallory', 'hunter2hunter2')
        ..seedFavorite('mallory', 1);

      await pumpLoggedIn(tester, backend);

      expect(favoriteButton(), findsOneWidget);
      expect(unfavoriteButton(), findsNothing);
    });

    testWidgets('点一下收藏，图标点亮且真的发出去了', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend()
        ..seedAccount('xiaoming', 'hunter2hunter2');
      await pumpLoggedIn(tester, backend);

      await tester.tap(favoriteButton());
      await tester.pumpAndSettle();

      expect(backend.favorites['xiaoming'], <int>[1]);
      expect(unfavoriteButton(), findsOneWidget);
      expect(
        backend.requests.any((Uri uri) => uri.path == '/api/favorites'),
        isTrue,
      );
    });

    testWidgets('再点一下取消收藏', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend()
        ..seedAccount('xiaoming', 'hunter2hunter2');
      await pumpLoggedIn(tester, backend);

      await tester.tap(favoriteButton());
      await tester.pumpAndSettle();
      await tester.tap(unfavoriteButton());
      await tester.pumpAndSettle();

      expect(backend.favorites['xiaoming'], isEmpty);
      expect(favoriteButton(), findsOneWidget);
    });

    testWidgets('收藏失败时图标不翻过去，并说明原因', (WidgetTester tester) async {
      // 这条是这一组里最要紧的：失败了却把图标点亮，
      // 用户会以为收藏成功了，下次打开却发现没有。
      final FakeBackend backend = FakeBackend()
        ..seedAccount('xiaoming', 'hunter2hunter2')
        ..favoriteErrorStatus = 500
        ..favoriteErrorMessage = '服务器内部错误';

      await pumpLoggedIn(tester, backend);

      await tester.tap(favoriteButton());
      await tester.pump();
      await tester.pump();

      expect(favoriteButton(), findsOneWidget, reason: '失败就不该点亮');
      expect(unfavoriteButton(), findsNothing);
      expect(find.text('服务器内部错误'), findsOneWidget);

      // 让 SnackBar 的计时器走完，避免测试结束时留下未处理的 Timer
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('提交中按钮不可用，连点不会发出第二个请求', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend()
        ..seedAccount('xiaoming', 'hunter2hunter2');
      final AuthController auth = backend.authController();
      // 登录**之后**才加延迟：在 fake async 里，测试体直接 await 的
      // 请求没人替它推进时钟，加了延迟会一直挂住
      await auth.login(username: 'xiaoming', password: 'hunter2hunter2');
      backend.delay = const Duration(milliseconds: 300);

      await pumpDetail(tester, backend, controller: auth);

      await tester.tap(favoriteButton());
      await tester.pump();

      final IconButton button = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(Icons.bookmark_border_rounded),
          matching: find.byType(IconButton),
        ),
      );
      expect(button.onPressed, isNull, reason: '提交中必须置灰');

      await tester.tap(favoriteButton(), warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      final int posts = backend.requests
          .where((Uri uri) => uri.path == '/api/favorites')
          .length;
      expect(posts, 1);
    });

    testWidgets('登录状态变了之后按钮跟着变', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend()
        ..seedAccount('xiaoming', 'hunter2hunter2');
      final AuthController auth = await pumpLoggedIn(tester, backend);
      expect(favoriteButton(), findsOneWidget);

      await auth.logout();
      await tester.pumpAndSettle();

      // 登出后仍能读正文，按钮回到未收藏形态
      expect(find.text('宿舍发生火灾如何正确逃生'), findsWidgets);
      expect(favoriteButton(), findsOneWidget);
      expect(unfavoriteButton(), findsNothing);
    });
  });

  group('没有 AuthScope 时', () {
    testWidgets('不显示收藏按钮，但正文照常显示', (WidgetTester tester) async {
      // 放一个点了没反应的图标比没有更糟
      final FakeBackend backend = FakeBackend();

      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: KnowledgeDetailPage(knowledgeId: 1, api: backend.api()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('宿舍发生火灾如何正确逃生'), findsWidgets);
      expect(favoriteButton(), findsNothing);
      expect(unfavoriteButton(), findsNothing);
    });
  });
}
