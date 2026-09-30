import 'package:anzhi/core/auth_controller.dart';
import 'package:anzhi/pages/favorites_page.dart';
import 'package:anzhi/pages/knowledge_detail_page.dart';
import 'package:anzhi/pages/login_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_backend.dart';

/// 安知 —— 我的收藏页（阶段 11b）
///
/// 重点关注三件事：
///   · 未登录时说「请先登录」，而不是「暂无收藏」
///     —— 后者是在骗人：不是没有，是不知道你是谁
///   · 取消收藏之后那一行要立刻消失
///   · 从详情页取消收藏回来，列表要跟着更新
void main() {
  Future<AuthController> pumpFavorites(
    WidgetTester tester,
    FakeBackend backend, {
    AuthController? controller,
  }) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final AuthController auth = controller ?? backend.authController();
    await tester.pumpWidget(
      AuthScope(
        controller: auth,
        child: const MaterialApp(home: FavoritesPage()),
      ),
    );
    await tester.pumpAndSettle();
    return auth;
  }

  /// 建一个已登录、且已经收藏了两条的账号
  Future<AuthController> loggedInWithTwo(
    WidgetTester tester,
    FakeBackend backend,
  ) async {
    backend
      ..seedAccount('xiaoming', 'hunter2hunter2')
      ..seedFavorite('xiaoming', 1)
      ..seedFavorite('xiaoming', 2);

    final AuthController auth = backend.authController();
    await auth.login(username: 'xiaoming', password: 'hunter2hunter2');
    return pumpFavorites(tester, backend, controller: auth);
  }

  group('未登录', () {
    testWidgets('说「请先登录」并给出去登录的入口', (WidgetTester tester) async {
      await pumpFavorites(tester, FakeBackend());

      expect(find.text('请先登录'), findsOneWidget);
      // 显示「还没有收藏」是不对的 —— 不是没有，是不知道你是谁
      expect(find.text('还没有收藏'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, '去登录'), findsOneWidget);
    });

    testWidgets('点「去登录」能进登录页', (WidgetTester tester) async {
      await pumpFavorites(tester, FakeBackend());

      await tester.tap(find.widgetWithText(OutlinedButton, '去登录'));
      await tester.pumpAndSettle();

      expect(find.byType(LoginPage), findsOneWidget);
    });
  });

  group('已登录', () {
    testWidgets('没有任何收藏时如实说明怎么收藏', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend()
        ..seedAccount('xiaoming', 'hunter2hunter2');
      final AuthController auth = backend.authController();
      await auth.login(username: 'xiaoming', password: 'hunter2hunter2');

      await pumpFavorites(tester, backend, controller: auth);

      expect(find.text('还没有收藏'), findsOneWidget);
      expect(find.textContaining('书签'), findsOneWidget);
      expect(find.text('请先登录'), findsNothing);
    });

    testWidgets('列出收藏的条目，最新的在最前面', (WidgetTester tester) async {
      await loggedInWithTwo(tester, FakeBackend());

      expect(find.text('宿舍发生火灾如何正确逃生'), findsOneWidget);
      expect(find.text('识别电信诈骗的五个通用信号'), findsOneWidget);
      expect(find.text('共 2 条收藏'), findsOneWidget);
    });

    testWidgets('看不到别人的收藏', (WidgetTester tester) async {
      // 收藏是跟着账号走的，这条挂了就是越权读取
      final FakeBackend backend = FakeBackend()
        ..seedAccount('xiaoming', 'hunter2hunter2')
        ..seedAccount('mallory', 'hunter2hunter2')
        ..seedFavorite('mallory', 1);

      final AuthController auth = backend.authController();
      await auth.login(username: 'xiaoming', password: 'hunter2hunter2');

      await pumpFavorites(tester, backend, controller: auth);

      expect(find.text('还没有收藏'), findsOneWidget);
      expect(find.text('宿舍发生火灾如何正确逃生'), findsNothing);
    });

    testWidgets('取消收藏后那一行立刻消失，计数也跟着减', (WidgetTester tester) async {
      // 用户刚说了不要它，还留在原地只会让人以为没生效
      final FakeBackend backend = FakeBackend();
      await loggedInWithTwo(tester, backend);

      await tester.tap(find.byTooltip('取消收藏').first);
      await tester.pumpAndSettle();

      expect(find.text('识别电信诈骗的五个通用信号'), findsNothing);
      expect(find.text('宿舍发生火灾如何正确逃生'), findsOneWidget);
      expect(find.text('共 1 条收藏'), findsOneWidget);
      expect(backend.favorites['xiaoming'], <int>[1]);
    });

    testWidgets('取消失败时那一行留在原地并说明原因', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend();
      await loggedInWithTwo(tester, backend);
      backend
        ..favoriteErrorStatus = 500
        ..favoriteErrorMessage = '服务器内部错误';

      await tester.tap(find.byTooltip('取消收藏').first);
      await tester.pumpAndSettle();

      expect(find.text('共 2 条收藏'), findsOneWidget);
      expect(find.text('服务器内部错误'), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('点条目进详情页，回来时列表已刷新', (WidgetTester tester) async {
      // 详情页里也能取消收藏 —— 不刷新的话回来会留着一行已经不在收藏里的内容
      final FakeBackend backend = FakeBackend();
      final AuthController auth = await loggedInWithTwo(tester, backend);

      await tester.tap(find.text('宿舍发生火灾如何正确逃生'));
      await tester.pumpAndSettle();
      expect(find.byType(KnowledgeDetailPage), findsOneWidget);

      // 在详情页取消收藏
      expect(find.byTooltip('取消收藏'), findsOneWidget);
      await tester.tap(find.byTooltip('取消收藏'));
      await tester.pumpAndSettle();

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(auth.isLoggedIn, isTrue);
      expect(find.text('共 1 条收藏'), findsOneWidget);
      expect(find.text('宿舍发生火灾如何正确逃生'), findsNothing);
    });

    testWidgets('登录状态下被登出，页面切成「请先登录」', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend();
      final AuthController auth = await loggedInWithTwo(tester, backend);

      await auth.logout();
      await tester.pumpAndSettle();

      expect(find.text('请先登录'), findsOneWidget);
      expect(find.text('宿舍发生火灾如何正确逃生'), findsNothing);
    });

    testWidgets('加载失败时给原因和重试按钮，而不是显示「还没有收藏」', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend()
        ..seedAccount('xiaoming', 'hunter2hunter2');
      final AuthController auth = backend.authController();
      await auth.login(username: 'xiaoming', password: 'hunter2hunter2');
      backend.errorStatus = 500;
      backend.errorBody = <String, dynamic>{'detail': '服务器内部错误'};

      await pumpFavorites(tester, backend, controller: auth);

      expect(find.text('服务器内部错误'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '重试'), findsOneWidget);
      expect(find.text('还没有收藏'), findsNothing, reason: '加载失败不能伪装成「没有收藏」');
    });
  });
}
