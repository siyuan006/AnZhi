import 'package:anzhi/core/auth_controller.dart';
import 'package:anzhi/pages/login_page.dart';
import 'package:anzhi/pages/profile_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_backend.dart';

/// 安知 —— 我的页面测试（阶段 11）
///
/// 重点是登录 / 未登录两种形态，以及「没登录时点收藏会怎样」——
/// 那一步最容易做成「弹一句请先登录就没了」。
void main() {
  Future<AuthController> pumpProfile(
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
        child: const MaterialApp(home: ProfilePage()),
      ),
    );
    await tester.pumpAndSettle();
    return auth;
  }

  group('未登录', () {
    testWidgets('显示未登录，并说明登录有什么用', (WidgetTester tester) async {
      await pumpProfile(tester, FakeBackend());

      expect(find.text('未登录'), findsOneWidget);
      expect(find.text('登录后可以收藏知识、保留浏览历史'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '登录'), findsOneWidget);
    });

    testWidgets('点「我的收藏」会打开登录页，而不是只弹一句提示', (WidgetTester tester) async {
      // 用户点了「我的收藏」，意图是明确的：
      // 直接给他登录入口，比让他自己回头找要顺手
      await pumpProfile(tester, FakeBackend());

      await tester.tap(find.text('我的收藏'));
      await tester.pumpAndSettle();

      expect(find.byType(LoginPage), findsOneWidget);
    });

    testWidgets('点「浏览历史」同样打开登录页', (WidgetTester tester) async {
      await pumpProfile(tester, FakeBackend());

      await tester.tap(find.text('浏览历史'));
      await tester.pumpAndSettle();

      expect(find.byType(LoginPage), findsOneWidget);
    });

    testWidgets('登录页里登录成功后，我的页面立刻变成已登录形态', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend()
        ..seedAccount('xiaoming', 'hunter2hunter2');
      await pumpProfile(tester, backend);

      await tester.tap(find.text('我的收藏'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, '用户名'),
        'xiaoming',
      );
      await tester.enterText(
        find.widgetWithText(TextField, '密码'),
        'hunter2hunter2',
      );
      await tester.tap(find.widgetWithText(FilledButton, '登录'));
      await tester.pumpAndSettle();

      // 回到我的页面，且已登录
      expect(find.text('我的收藏'), findsOneWidget);
      expect(find.text('未登录'), findsNothing);
      expect(find.text('@xiaoming'), findsOneWidget);
    });
  });

  group('已登录', () {
    Future<AuthController> pumpLoggedIn(
      WidgetTester tester,
      FakeBackend backend,
    ) async {
      final AuthController auth = backend.authController();
      await auth.login(username: 'xiaoming', password: 'hunter2hunter2');
      return pumpProfile(tester, backend, controller: auth);
    }

    testWidgets('显示昵称与用户名，按钮变成退出', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend()
        ..seedAccount('xiaoming', 'hunter2hunter2', nickname: '小明');

      await pumpLoggedIn(tester, backend);

      expect(find.text('小明'), findsOneWidget);
      expect(find.text('@xiaoming'), findsOneWidget);
      expect(find.text('退出'), findsOneWidget);
      expect(find.text('未登录'), findsNothing);
    });

    testWidgets('没有昵称时显示用户名', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend()
        ..seedAccount('xiaoming', 'hunter2hunter2');

      await pumpLoggedIn(tester, backend);

      expect(find.text('xiaoming'), findsOneWidget);
    });

    /// 确认弹窗里的按钮。
    ///
    /// 必须限定在 AlertDialog 内：「退出」两个字在页头按钮和
    /// 弹窗按钮上各有一个，直接 find.text('退出') 会命中两个而报错。
    Finder dialogButton(String label) => find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(TextButton, label),
        );

    testWidgets('退出前会先确认', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend()
        ..seedAccount('xiaoming', 'hunter2hunter2');
      final AuthController auth = await pumpLoggedIn(tester, backend);

      // 页头的「退出」是唯一的
      await tester.tap(find.widgetWithText(TextButton, '退出'));
      await tester.pumpAndSettle();
      expect(find.text('退出后需要重新输入用户名和密码。'), findsOneWidget);

      // 取消：仍然是登录态
      await tester.tap(dialogButton('取消'));
      await tester.pumpAndSettle();
      expect(auth.isLoggedIn, isTrue);

      // 再点一次并确认：退出
      await tester.tap(find.widgetWithText(TextButton, '退出'));
      await tester.pumpAndSettle();
      await tester.tap(dialogButton('退出'));
      await tester.pumpAndSettle();

      expect(auth.isLoggedIn, isFalse);
      expect(find.text('未登录'), findsOneWidget);
    });

    testWidgets('退出后点收藏会重新要求登录', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend()
        ..seedAccount('xiaoming', 'hunter2hunter2');
      final AuthController auth = await pumpLoggedIn(tester, backend);

      await tester.tap(find.widgetWithText(TextButton, '退出'));
      await tester.pumpAndSettle();
      await tester.tap(dialogButton('退出'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('我的收藏'));
      await tester.pumpAndSettle();

      expect(auth.isLoggedIn, isFalse);
      expect(find.byType(LoginPage), findsOneWidget);
    });
  });

  group('尚未实现的入口', () {
    testWidgets('社区与个性化入口如实标注阶段', (WidgetTester tester) async {
      await pumpProfile(tester, FakeBackend());

      expect(find.text('阶段 12'), findsOneWidget);
      expect(find.text('阶段 13'), findsNWidgets(3));
    });

    testWidgets('点未实现的入口提示计划阶段', (WidgetTester tester) async {
      await pumpProfile(tester, FakeBackend());

      await tester.tap(find.text('我的帖子'));
      await tester.pumpAndSettle();

      expect(find.textContaining('阶段 12'), findsWidgets);
    });

    testWidgets('关于安知有实际内容', (WidgetTester tester) async {
      await pumpProfile(tester, FakeBackend());

      await tester.tap(find.text('关于安知'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Flutter · FastAPI · SQLite · DeepSeek'), findsOneWidget);
    });
  });

  group('没有 AuthScope 时', () {
    testWidgets('页面仍能渲染，不崩溃', (WidgetTester tester) async {
      // 单独 pump 这个页面（不套 AuthScope）时按未登录处理，
      // 而不是显示一个点了会崩的按钮
      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        const MaterialApp(home: ProfilePage()),
      );
      await tester.pumpAndSettle();

      expect(find.text('未登录'), findsOneWidget);
      expect(find.text('退出'), findsNothing);
    });
  });
}
