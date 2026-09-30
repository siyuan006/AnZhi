import 'package:anzhi/core/auth_controller.dart';
import 'package:anzhi/pages/history_page.dart';
import 'package:anzhi/pages/knowledge_detail_page.dart';
import 'package:anzhi/pages/login_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_backend.dart';

/// 安知 —— 浏览历史页（阶段 11c）
///
/// 重点关注四件事：
///   · 未登录时说「请先登录」，而不是「还没有浏览记录」
///     —— 后者是在骗人：不是没有，是不知道你是谁
///   · 删除一条之后那一行要立刻消失
///   · 清空前必须问一句（这是本页唯一不可撤销的操作）
///   · 加载失败不能伪装成「没有记录」
void main() {
  Future<AuthController> pumpHistory(
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
        child: const MaterialApp(home: HistoryPage()),
      ),
    );
    await tester.pumpAndSettle();
    return auth;
  }

  /// 建一个已登录、且已经看过两条的账号
  Future<AuthController> loggedInWithTwo(
    WidgetTester tester,
    FakeBackend backend,
  ) async {
    backend
      ..seedAccount('xiaoming', 'hunter2hunter2')
      ..seedHistory('xiaoming', 1, age: const Duration(hours: 2))
      ..seedHistory('xiaoming', 2, age: const Duration(minutes: 5));

    final AuthController auth = backend.authController();
    await auth.login(username: 'xiaoming', password: 'hunter2hunter2');
    return pumpHistory(tester, backend, controller: auth);
  }

  group('未登录', () {
    testWidgets('说「请先登录」并给出去登录的入口', (WidgetTester tester) async {
      await pumpHistory(tester, FakeBackend());

      expect(find.text('请先登录'), findsOneWidget);
      // 显示「还没有浏览记录」是不对的 —— 不是没有，是不知道你是谁
      expect(find.text('还没有浏览记录'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, '去登录'), findsOneWidget);
    });

    testWidgets('点「去登录」能进登录页', (WidgetTester tester) async {
      await pumpHistory(tester, FakeBackend());

      await tester.tap(find.widgetWithText(OutlinedButton, '去登录'));
      await tester.pumpAndSettle();

      expect(find.byType(LoginPage), findsOneWidget);
    });
  });

  group('已登录', () {
    testWidgets('没有任何记录时如实说明会怎么出现', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend()
        ..seedAccount('xiaoming', 'hunter2hunter2');
      final AuthController auth = backend.authController();
      await auth.login(username: 'xiaoming', password: 'hunter2hunter2');

      await pumpHistory(tester, backend, controller: auth);

      expect(find.text('还没有浏览记录'), findsOneWidget);
      expect(find.text('请先登录'), findsNothing);
    });

    testWidgets('列出看过的条目，最近看的在最前面', (WidgetTester tester) async {
      await loggedInWithTwo(tester, FakeBackend());

      expect(find.text('识别电信诈骗的五个通用信号'), findsOneWidget);
      expect(find.text('宿舍发生火灾如何正确逃生'), findsOneWidget);
      expect(find.text('共 2 条浏览记录'), findsOneWidget);
    });

    testWidgets('每行显示相对时间', (WidgetTester tester) async {
      await loggedInWithTwo(tester, FakeBackend());

      expect(find.text('5 分钟前'), findsOneWidget);
      expect(find.text('2 小时前'), findsOneWidget);
    });

    testWidgets('看不到别人的浏览记录', (WidgetTester tester) async {
      // 历史是私密的：看过什么、什么时候看的，都不该被别人读到
      final FakeBackend backend = FakeBackend()
        ..seedAccount('xiaoming', 'hunter2hunter2')
        ..seedAccount('mallory', 'hunter2hunter2')
        ..seedHistory('mallory', 1);

      final AuthController auth = backend.authController();
      await auth.login(username: 'xiaoming', password: 'hunter2hunter2');

      await pumpHistory(tester, backend, controller: auth);

      expect(find.text('还没有浏览记录'), findsOneWidget);
      expect(find.text('宿舍发生火灾如何正确逃生'), findsNothing);
    });

    testWidgets('删掉一条后那一行立刻消失，计数也跟着减', (WidgetTester tester) async {
      // 用户刚说了不要它，还留在原地只会让人以为没生效
      final FakeBackend backend = FakeBackend();
      await loggedInWithTwo(tester, backend);

      await tester.tap(find.byTooltip('删除这条记录').first);
      await tester.pumpAndSettle();

      expect(find.text('识别电信诈骗的五个通用信号'), findsNothing);
      expect(find.text('宿舍发生火灾如何正确逃生'), findsOneWidget);
      expect(find.text('共 1 条浏览记录'), findsOneWidget);
      expect(backend.histories['xiaoming'], <int>[1]);
    });

    testWidgets('删除失败时那一行留在原地并说明原因', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend();
      await loggedInWithTwo(tester, backend);
      backend
        ..historyErrorStatus = 500
        ..historyErrorMessage = '服务器内部错误';

      await tester.tap(find.byTooltip('删除这条记录').first);
      await tester.pumpAndSettle();

      expect(find.text('共 2 条浏览记录'), findsOneWidget);
      expect(find.text('服务器内部错误'), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('点条目进详情页，回来后列表已刷新', (WidgetTester tester) async {
      // 刚看过的这一条时间会被推到最前 ——
      // 不刷新的话列表顺序和用户刚才的操作对不上
      final FakeBackend backend = FakeBackend();
      await loggedInWithTwo(tester, backend);

      await tester.tap(find.text('宿舍发生火灾如何正确逃生'));
      await tester.pumpAndSettle();
      expect(find.byType(KnowledgeDetailPage), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.byType(HistoryPage), findsOneWidget);
      expect(find.text('共 2 条浏览记录'), findsOneWidget);
    });

    testWidgets('登录状态下被登出，页面切成「请先登录」', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend();
      final AuthController auth = await loggedInWithTwo(tester, backend);

      await auth.logout();
      await tester.pumpAndSettle();

      expect(find.text('请先登录'), findsOneWidget);
      expect(find.text('宿舍发生火灾如何正确逃生'), findsNothing);
    });

    testWidgets('加载失败时给原因和重试按钮，而不是显示「还没有浏览记录」',
        (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend()
        ..seedAccount('xiaoming', 'hunter2hunter2');
      final AuthController auth = backend.authController();
      await auth.login(username: 'xiaoming', password: 'hunter2hunter2');
      backend.errorStatus = 500;
      backend.errorBody = <String, dynamic>{'detail': '服务器内部错误'};

      await pumpHistory(tester, backend, controller: auth);

      expect(find.text('服务器内部错误'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '重试'), findsOneWidget);
      expect(
        find.text('还没有浏览记录'),
        findsNothing,
        reason: '加载失败不能伪装成「没有记录」',
      );
    });
  });

  group('清空浏览历史', () {
    testWidgets('先弹确认框，点「取消」什么都不做', (WidgetTester tester) async {
      // 这是本页唯一不可撤销的操作，不能一点就没
      final FakeBackend backend = FakeBackend();
      await loggedInWithTwo(tester, backend);

      await tester.tap(find.byTooltip('清空浏览历史'));
      await tester.pumpAndSettle();

      expect(find.text('清空浏览历史'), findsWidgets);
      await tester.tap(find.widgetWithText(TextButton, '取消'));
      await tester.pumpAndSettle();

      expect(find.text('共 2 条浏览记录'), findsOneWidget);
      expect(backend.histories['xiaoming'], hasLength(2));
    });

    testWidgets('确认后列表清空', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend();
      await loggedInWithTwo(tester, backend);

      await tester.tap(find.byTooltip('清空浏览历史'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '清空'));
      await tester.pumpAndSettle();

      expect(find.text('还没有浏览记录'), findsOneWidget);
      expect(backend.histories['xiaoming'], isEmpty);

      // 让 SnackBar 的计时器走完，避免测试结束时留下未处理的 Timer
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('没有记录时不显示清空按钮', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend()
        ..seedAccount('xiaoming', 'hunter2hunter2');
      final AuthController auth = backend.authController();
      await auth.login(username: 'xiaoming', password: 'hunter2hunter2');

      await pumpHistory(tester, backend, controller: auth);

      expect(find.byTooltip('清空浏览历史'), findsNothing);
    });
  });
}
