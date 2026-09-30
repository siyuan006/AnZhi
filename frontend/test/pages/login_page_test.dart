import 'package:anzhi/core/auth_controller.dart';
import 'package:anzhi/pages/login_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_backend.dart';

/// 安知 —— 登录 / 注册页测试（阶段 11）
///
/// 三处最容易做错的地方：
///  · 提交中还能重复点，发出两个注册请求
///  · 失败提示说「登录失败」却不说是用户名错还是密码错（或反过来乱猜）
///  · 把密码留在某个还能读到的对象里
void main() {
  Future<AuthController> pumpLogin(
    WidgetTester tester,
    FakeBackend backend, {
    AuthController? controller,
  }) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final AuthController auth = controller ?? backend.authController();
    await tester.pumpWidget(
      AuthScope(
        controller: auth,
        child: MaterialApp(home: const LoginPage()),
      ),
    );
    return auth;
  }

  Future<void> fill(
    WidgetTester tester, {
    required String username,
    required String password,
  }) async {
    await tester.enterText(find.widgetWithText(TextField, '用户名'), username);
    await tester.enterText(find.widgetWithText(TextField, '密码'), password);
  }

  group('登录', () {
    testWidgets('登录成功后返回上一页并进入登录态', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend()
        ..seedAccount('xiaoming', 'hunter2hunter2');
      final AuthController auth = await pumpLogin(tester, backend);

      await fill(tester, username: 'xiaoming', password: 'hunter2hunter2');
      await tester.tap(find.widgetWithText(FilledButton, '登录'));
      await tester.pumpAndSettle();

      expect(auth.isLoggedIn, isTrue);
      expect(find.byType(LoginPage), findsNothing, reason: '成功后应该退出登录页');
    });

    testWidgets('密码错误时显示后端给的中文说明', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend()
        ..seedAccount('xiaoming', 'hunter2hunter2');
      final AuthController auth = await pumpLogin(tester, backend);

      await fill(tester, username: 'xiaoming', password: 'wrong-password');
      await tester.tap(find.widgetWithText(FilledButton, '登录'));
      await tester.pumpAndSettle();

      expect(find.text('用户名或密码不正确'), findsOneWidget);
      expect(auth.isLoggedIn, isFalse);
    });

    testWidgets('用户名不存在时提示与密码错误完全相同', (WidgetTester tester) async {
      // 两种情况给出不同提示，等于对外提供了一个
      // 「这个用户名注册过没有」的查询接口
      final FakeBackend backend = FakeBackend()
        ..seedAccount('xiaoming', 'hunter2hunter2');
      await pumpLogin(tester, backend);

      await fill(tester, username: 'nobody', password: 'hunter2hunter2');
      await tester.tap(find.widgetWithText(FilledButton, '登录'));
      await tester.pumpAndSettle();

      expect(find.text('用户名或密码不正确'), findsOneWidget);
    });

    testWidgets('连不上后端时如实说明', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend()..offline = true;
      await pumpLogin(tester, backend);

      await fill(tester, username: 'xiaoming', password: 'hunter2hunter2');
      await tester.tap(find.widgetWithText(FilledButton, '登录'));
      await tester.pumpAndSettle();

      expect(find.textContaining('无法连接到服务器'), findsOneWidget);
    });

    testWidgets('空着不填时不发请求，直接提示', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend();
      await pumpLogin(tester, backend);

      await tester.tap(find.widgetWithText(FilledButton, '登录'));
      await tester.pumpAndSettle();

      expect(find.text('用户名和密码都要填'), findsOneWidget);
      expect(backend.requests, isEmpty, reason: '必然失败的往返不必发出去');
    });

    testWidgets('提交中重复点击不会发出第二个请求', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend()
        ..seedAccount('xiaoming', 'hunter2hunter2')
        ..delay = const Duration(milliseconds: 300);
      await pumpLogin(tester, backend);

      await fill(tester, username: 'xiaoming', password: 'hunter2hunter2');
      await tester.tap(find.widgetWithText(FilledButton, '登录'));
      await tester.pump();

      final FilledButton button =
          tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull, reason: '提交中按钮必须不可用');

      await tester.tap(find.byType(FilledButton), warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      final int logins = backend.requests
          .where((Uri uri) => uri.path == '/api/auth/login')
          .length;
      expect(logins, 1);
    });

    testWidgets('错误提示在切换模式后消失', (WidgetTester tester) async {
      // 上一条提示是针对「登录」的，切到注册还留着会让人以为
      // 当前这个表单也有问题
      final FakeBackend backend = FakeBackend()
        ..seedAccount('xiaoming', 'hunter2hunter2');
      await pumpLogin(tester, backend);

      await fill(tester, username: 'xiaoming', password: 'wrong-password');
      await tester.tap(find.widgetWithText(FilledButton, '登录'));
      await tester.pumpAndSettle();
      expect(find.text('用户名或密码不正确'), findsOneWidget);

      await tester.tap(find.text('还没有账号？去注册'));
      await tester.pumpAndSettle();

      expect(find.text('用户名或密码不正确'), findsNothing);
    });
  });

  group('注册', () {
    testWidgets('切换到注册模式会多出昵称输入框', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend();
      await pumpLogin(tester, backend);

      expect(find.widgetWithText(TextField, '昵称（可留空）'), findsNothing);

      await tester.tap(find.text('还没有账号？去注册'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextField, '昵称（可留空）'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '注册并登录'), findsOneWidget);
    });

    testWidgets('注册成功后直接进入登录态', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend();
      final AuthController auth = await pumpLogin(tester, backend);

      await tester.tap(find.text('还没有账号？去注册'));
      await tester.pumpAndSettle();
      await fill(tester, username: 'newbie', password: 'hunter2hunter2');
      await tester.tap(find.widgetWithText(FilledButton, '注册并登录'));
      await tester.pumpAndSettle();

      expect(auth.isLoggedIn, isTrue);
      expect(auth.user!.username, 'newbie');
    });

    testWidgets('用户名重复时转达后端的说明', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend()
        ..seedAccount('taken', 'hunter2hunter2');
      await pumpLogin(tester, backend);

      await tester.tap(find.text('还没有账号？去注册'));
      await tester.pumpAndSettle();
      await fill(tester, username: 'taken', password: 'hunter2hunter2');
      await tester.tap(find.widgetWithText(FilledButton, '注册并登录'));
      await tester.pumpAndSettle();

      expect(find.text('该用户名已被注册'), findsOneWidget);
    });

    testWidgets('密码过短时转达后端的说明，而不是自己编一条', (WidgetTester tester) async {
      // 长度规则只由后端判定：两处各写一份迟早会不一致
      final FakeBackend backend = FakeBackend();
      await pumpLogin(tester, backend);

      await tester.tap(find.text('还没有账号？去注册'));
      await tester.pumpAndSettle();
      await fill(tester, username: 'newbie', password: 'abc');
      await tester.tap(find.widgetWithText(FilledButton, '注册并登录'));
      await tester.pumpAndSettle();

      expect(find.text('密码至少 8 位'), findsOneWidget);
    });

    testWidgets('昵称可以留空', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend();
      final AuthController auth = await pumpLogin(tester, backend);

      await tester.tap(find.text('还没有账号？去注册'));
      await tester.pumpAndSettle();
      await fill(tester, username: 'newbie', password: 'hunter2hunter2');
      await tester.tap(find.widgetWithText(FilledButton, '注册并登录'));
      await tester.pumpAndSettle();

      expect(auth.isLoggedIn, isTrue);
      expect(auth.user!.displayName, 'newbie');
    });
  });

  group('口令输入框', () {
    testWidgets('默认遮蔽，可以点眼睛切换', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend();
      await pumpLogin(tester, backend);

      TextField passwordField() =>
          tester.widget<TextField>(find.widgetWithText(TextField, '密码'));

      expect(passwordField().obscureText, isTrue);

      await tester.tap(find.byTooltip('显示密码'));
      await tester.pumpAndSettle();

      expect(passwordField().obscureText, isFalse);
    });

    testWidgets('输入法不记忆密码', (WidgetTester tester) async {
      // 口令不该进入输入法词库
      final FakeBackend backend = FakeBackend();
      await pumpLogin(tester, backend);

      final TextField field =
          tester.widget<TextField>(find.widgetWithText(TextField, '密码'));

      expect(field.enableSuggestions, isFalse);
      expect(field.autocorrect, isFalse);
    });

    testWidgets('提交后密码控件被销毁，不留在页面里', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend()
        ..seedAccount('xiaoming', 'hunter2hunter2');
      await pumpLogin(tester, backend);

      await fill(tester, username: 'xiaoming', password: 'hunter2hunter2');
      await tester.tap(find.widgetWithText(FilledButton, '登录'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextField, '密码'), findsNothing);
    });
  });

  group('不登录也能用', () {
    testWidgets('页面上明确说明不登录不影响查知识、问 AI', (WidgetTester tester) async {
      // 安知是安全科普应用。用户若以为必须先注册，
      // 可能在紧急时刻把自己劝退 —— 这句话是功能的一部分，不是装饰
      final FakeBackend backend = FakeBackend();
      await pumpLogin(tester, backend);

      expect(find.textContaining('不登录也能查看安全知识'), findsOneWidget);
    });
  });
}
