import 'package:anzhi/core/app_constants.dart';
import 'package:anzhi/core/auth_controller.dart';
import 'package:anzhi/pages/settings_follow_page.dart';
import 'package:anzhi/pages/settings_home_page.dart';
import 'package:anzhi/pages/settings_notify_page.dart';
import 'package:anzhi/services/settings_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_backend.dart';

/// 安知 —— 个性化设置三页测试（阶段 13b）
///
/// 三页共用 `SettingsPageShell`，重点因此分两层：
///
/// **共用的部分**（未登录怎么说、拉不到怎么办）
///   · 未登录如实说「请先登录」，而不是显示「没有关注任何领域」
///     —— 不是没有，是不知道你是谁
///   · 拉不到设置要能重试，不能显示成一份空设置让用户以为都被清空了
///
/// **各页自己的部分**
///   · 点开关必须**把算好的完整数组**发出去，不是「加一个/减一个」
///   · **没改的字段不能出现在请求体里** —— 分区更新的语义，
///     界面上完全看不出来，顺手全塞进去会把另外两项覆盖掉
///   · **空数组是「全取消」，不是「不改」** —— 这两者混淆的话，
///     用户永远取消不掉最后一个关注 / 关不掉最后一个模块
///   · 保存失败时开关必须停在原处并说明原因
void main() {
  Future<void> pumpPage(
    WidgetTester tester,
    FakeBackend backend, {
    required Widget Function({SettingsApi? api}) build,
    bool loggedIn = true,
    String username = 'alice',
    void Function()? afterLogin,
  }) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final AuthController auth = backend.authController();
    if (loggedIn) {
      backend.seedAccount(username, 'hunter2hunter2', nickname: '小艾');
      await auth.login(username: username, password: 'hunter2hunter2');
    }

    // 错误开关要等登录之后再打开：提前打开的话登录请求自己就先挂了，
    // 页面会显示「请先登录」，测的就成了另一回事
    afterLogin?.call();

    await tester.pumpWidget(
      AuthScope(
        controller: auth,
        // 用 authController 的客户端：三页的接口都要登录
        child: MaterialApp(home: build(api: auth.settingsApi)),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpFollow(
    WidgetTester tester,
    FakeBackend backend, {
    bool loggedIn = true,
    void Function()? afterLogin,
  }) =>
      pumpPage(
        tester,
        backend,
        build: ({SettingsApi? api}) => SettingsFollowPage(api: api),
        loggedIn: loggedIn,
        afterLogin: afterLogin,
      );

  Future<void> pumpHome(
    WidgetTester tester,
    FakeBackend backend, {
    bool loggedIn = true,
    void Function()? afterLogin,
  }) =>
      pumpPage(
        tester,
        backend,
        build: ({SettingsApi? api}) => SettingsHomePage(api: api),
        loggedIn: loggedIn,
        afterLogin: afterLogin,
      );

  Future<void> pumpNotify(
    WidgetTester tester,
    FakeBackend backend, {
    bool loggedIn = true,
    void Function()? afterLogin,
  }) =>
      pumpPage(
        tester,
        backend,
        build: ({SettingsApi? api}) => SettingsNotifyPage(api: api),
        loggedIn: loggedIn,
        afterLogin: afterLogin,
      );

  /// 某个开关当前是开还是关。
  ///
  /// 先找到那一行，再从行里找开关 —— 开关和标题在 `ListTile` 里是
  /// 平级的，不是祖先关系。
  bool switchOf(WidgetTester tester, String title) {
    final Finder tile = find.ancestor(
      of: find.text(title),
      matching: find.byType(ListTile),
    );
    final Finder toggle = find.descendant(of: tile, matching: find.byType(Switch));
    return tester.widget<Switch>(toggle).value;
  }

  Future<void> tapSwitch(WidgetTester tester, String title) async {
    await tester.tap(find.text(title));
    await tester.pumpAndSettle();
  }

  // -------------------------------------------------------------------------
  // 三页共用的部分
  // -------------------------------------------------------------------------

  group('未登录', () {
    testWidgets('关注领域如实说「请先登录」', (WidgetTester tester) async {
      await pumpFollow(tester, FakeBackend(), loggedIn: false);

      expect(find.text('请先登录'), findsOneWidget, reason: '不是「没有关注任何领域」');
      expect(find.text('去登录'), findsOneWidget);
      expect(find.byType(Switch), findsNothing, reason: '没登录就没有开关可拨');
    });

    testWidgets('首页布局如实说「请先登录」', (WidgetTester tester) async {
      await pumpHome(tester, FakeBackend(), loggedIn: false);

      expect(find.text('请先登录'), findsOneWidget);
    });

    testWidgets('通知设置如实说「请先登录」', (WidgetTester tester) async {
      await pumpNotify(tester, FakeBackend(), loggedIn: false);

      expect(find.text('请先登录'), findsOneWidget);
    });
  });

  group('拉不到设置', () {
    testWidgets('说明拉不到并给重试，而不是显示成一份空设置', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend();

      await pumpPage(
        tester,
        backend,
        build: ({SettingsApi? api}) => SettingsFollowPage(api: api),
        afterLogin: () => backend.settingsErrorStatus = 500,
      );

      expect(find.text('设置保存失败，请稍后再试'), findsOneWidget);
      expect(
        find.text('重试'),
        findsOneWidget,
        reason: '拉不到要给一条重试的路，不能只留一句错误',
      );
      expect(
        find.byType(Switch),
        findsNothing,
        reason: '拉不到的时候不能显示成「全部未关注」—— 那是假的',
      );
    });
  });

  // -------------------------------------------------------------------------
  // 关注领域
  // -------------------------------------------------------------------------

  group('关注领域', () {
    testWidgets('第一次打开时全部未关注', (WidgetTester tester) async {
      await pumpFollow(tester, FakeBackend());

      expect(
        find.byType(Switch),
        findsNWidgets(kCategories.length),
        reason: '六个领域一个不少地列出来',
      );
      expect(switchOf(tester, '消防安全'), isFalse);
    });

    testWidgets('已关注的在打开时就是打开的', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend()
        ..seedSettings('alice', followedCategories: <int>[1, 5]);

      await pumpFollow(tester, backend);

      expect(switchOf(tester, '消防安全'), isTrue);
      expect(switchOf(tester, '网络与反诈安全'), isTrue);
      expect(switchOf(tester, '用电安全'), isFalse);
    });

    testWidgets('点一下关注，请求里带上算好的完整数组', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend()
        ..seedSettings('alice', followedCategories: <int>[1]);

      await pumpFollow(tester, backend);
      await tapSwitch(tester, '交通安全');

      final Map<String, dynamic> body = backend.settingsUpdateRequests.single;
      expect(
        body['followed_categories'],
        <int>[1, 3],
        reason: '发的是整份列表而不是「加了哪一个」—— 增量接口丢包重试会加两次',
      );
    });

    testWidgets('请求体里只有改了的那一项', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend();

      await pumpFollow(tester, backend);
      await tapSwitch(tester, '消防安全');

      final Map<String, dynamic> body = backend.settingsUpdateRequests.single;
      expect(
        body.keys,
        <String>['followed_categories'],
        reason: '分区更新：顺手把 home_modules / notify_enabled 一起塞进去'
            '会把用户在别处做的设置覆盖掉，而界面上完全看不出来',
      );
    });

    testWidgets('取消最后一个关注后，请求里是空数组而不是没有这个字段', (
      WidgetTester tester,
    ) async {
      final FakeBackend backend = FakeBackend()
        ..seedSettings('alice', followedCategories: <int>[1]);

      await pumpFollow(tester, backend);
      await tapSwitch(tester, '消防安全');

      final Map<String, dynamic> body = backend.settingsUpdateRequests.single;
      expect(
        body.containsKey('followed_categories'),
        isTrue,
        reason: '空数组是「一个都不关注了」，不是「这次不改」—— '
            '两者混为一谈的话，最后这个关注永远取消不掉',
      );
      expect(body['followed_categories'], isEmpty);
      expect(switchOf(tester, '消防安全'), isFalse);
    });

    testWidgets('保存成功后页脚提示跟着变', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend();

      await pumpFollow(tester, backend);
      expect(find.text('当前没有关注任何领域，首页会按常规顺序推荐内容。'), findsOneWidget);

      await tapSwitch(tester, '消防安全');

      expect(find.text('已关注：消防安全'), findsOneWidget);
    });

    testWidgets('保存失败时开关停在原处并说明原因', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend();

      await pumpFollow(
        tester,
        backend,
        afterLogin: () => backend.settingsErrorStatus = 500,
      );

      // 拉取就已经失败了，这里只确认失败不会让开关翻过去
      expect(find.byType(Switch), findsNothing);
    });

    testWidgets('保存失败（拉取成功、写入失败）时开关不动', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend();

      await pumpFollow(tester, backend);

      // 拉取走完再让写入失败
      backend.settingsErrorStatus = 500;
      await tapSwitch(tester, '消防安全');

      expect(
        switchOf(tester, '消防安全'),
        isFalse,
        reason: '服务端说没存上，界面就不能显示成存上了',
      );
      expect(find.text('设置保存失败，请稍后再试'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  // 首页布局
  // -------------------------------------------------------------------------

  group('首页布局', () {
    testWidgets('没设置过时五个模块全开', (WidgetTester tester) async {
      await pumpHome(tester, FakeBackend());

      for (final HomeModule module in HomeModule.all) {
        expect(switchOf(tester, module.label), isTrue, reason: module.label);
      }
    });

    testWidgets('关掉一个模块，请求里带上剩下那些', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend();

      await pumpHome(tester, backend);
      await tapSwitch(tester, '社区精选');

      final Map<String, dynamic> body = backend.settingsUpdateRequests.single;
      expect(body.keys, <String>['home_modules']);
      expect(
        body['home_modules'],
        <String>['daily', 'recommend', 'category', 'ai'],
        reason: '顺序按首页从上到下，与后端 normalize_modules 一致',
      );
    });

    testWidgets('全部关掉会提前说清楚后果', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend()
        ..seedSettings('alice', homeModules: <String>['daily']);

      await pumpHome(tester, backend);
      expect(find.text('首页将按这个顺序显示：今日安全知识'), findsOneWidget);

      await tapSwitch(tester, '今日安全知识');

      expect(
        find.textContaining('所有模块都关掉了，首页会是空的'),
        findsOneWidget,
        reason: '允许用户关光，但要在他回首页看见空白之前就说清楚',
      );
      expect(backend.settings[usernameOf(backend)]!['home_modules'], isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // 通知设置
  // -------------------------------------------------------------------------

  group('通知设置', () {
    testWidgets('默认是打开的', (WidgetTester tester) async {
      await pumpNotify(tester, FakeBackend());

      expect(switchOf(tester, '接收安全提醒'), isTrue);
    });

    testWidgets('关掉时请求里只有这一项', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend();

      await pumpNotify(tester, backend);
      await tapSwitch(tester, '接收安全提醒');

      final Map<String, dynamic> body = backend.settingsUpdateRequests.single;
      expect(body, <String, dynamic>{'notify_enabled': false});
    });

    testWidgets('如实说明 V1.0 还没有推送功能', (WidgetTester tester) async {
      await pumpNotify(tester, FakeBackend());

      expect(
        find.textContaining('V1.0 还没有通知推送功能'),
        findsOneWidget,
        reason: '摆一个看起来在生效的开关是在骗用户 —— '
            '他以为关掉了推送，将来版本上线却被通知打扰',
      );
    });
  });
}

/// 假后端里只有一个账号时，它就是当前用户
String usernameOf(FakeBackend backend) => backend.accounts.keys.first;
