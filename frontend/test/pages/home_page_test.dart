import 'package:anzhi/core/auth_controller.dart';
import 'package:anzhi/pages/home_page.dart';
import 'package:anzhi/pages/login_page.dart';
import 'package:anzhi/pages/settings_home_page.dart';
import 'package:anzhi/pages/settings_notify_page.dart';
import 'package:anzhi/widgets/knowledge_tile.dart';
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

/// 三条知识，用来观察「今日拿走一条、推荐拿其余」
final List<Map<String, dynamic>> _threeItems = <Map<String, dynamic>>[
  for (int i = 0; i < 3; i++)
    <String, dynamic>{
      'id': i + 1,
      'title': '知识条目 ${i + 1}',
      'category_id': 1,
      'category_name': '消防安全',
      'summary': '摘要 ${i + 1}',
      'risk_level': 'low',
      'image_url': null,
      'created_at': '2026-09-30T10:00:00',
    },
];

/// 装好三条知识、并预置一份首页布局设置的假后端
FakeBackend _backendWith(
  List<Map<String, dynamic>> items, {
  required List<String> homeModules,
}) =>
    FakeBackend(items: items)..seedSettings('alice', homeModules: homeModules);

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

  // ---------------------------------------------------------------------------
  // 个性化（阶段 13d）
  // ---------------------------------------------------------------------------

  group('按设置显示模块', () {
    /// 登录后注入个性化设置，首页据此决定显示什么。
    ///
    /// 注入 `settingsApi` 之外还要套 `AuthScope` ——
    /// 首页要先知道「现在是不是登录状态」才决定发不发这个请求，
    /// 光给接口不告诉它登录了，它会一直按未登录处理。
    Future<AuthController> pumpLoggedIn(
      WidgetTester tester,
      FakeBackend backend, {
      bool withSettingsApi = true,
    }) async {
      await useTallWindow(tester);

      backend.seedAccount('alice', 'hunter2hunter2');
      final AuthController auth = backend.authController();
      await auth.login(username: 'alice', password: 'hunter2hunter2');

      await tester.pumpWidget(
        AuthScope(
          controller: auth,
          child: MaterialApp(
            home: HomePage(
              api: backend.api(),
              postApi: backend.postApi(),
              settingsApi: withSettingsApi ? auth.settingsApi : null,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return auth;
    }

    testWidgets('未登录时不请求设置，五个模块全显示', (WidgetTester tester) async {
      await useTallWindow(tester);
      final FakeBackend backend = FakeBackend();

      await tester.pumpWidget(
        AuthScope(
          controller: backend.authController(),
          child: MaterialApp(
            home: HomePage(api: backend.api(), postApi: backend.postApi()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 没登录就没有账号可谈，发出去只会拿到 401 ——
      // 那看起来像是后端坏了，而实际只是没登录
      expect(
        backend.requests.any((Uri url) => url.path == '/api/settings'),
        isFalse,
        reason: '未登录不该发这个请求',
      );
      expect(find.text('今日安全知识'), findsOneWidget);
      expect(find.text('安全分类'), findsOneWidget);
    });

    testWidgets('关掉的模块不渲染，其余照常', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend()
        ..seedSettings(
          'alice',
          homeModules: <String>['daily', 'category', 'community'],
        );

      await pumpLoggedIn(tester, backend);

      expect(find.text('今日安全知识'), findsOneWidget);
      expect(find.text('安全分类'), findsOneWidget);
      expect(find.text('社区精选'), findsOneWidget);
      expect(find.text('推荐知识'), findsNothing);
      expect(find.text('AI 安全助手'), findsNothing);
    });

    testWidgets('今日安全知识在时，推荐只拿剩下的', (WidgetTester tester) async {
      await pumpLoggedIn(
        tester,
        _backendWith(_threeItems, homeModules: <String>['daily', 'recommend']),
      );

      expect(find.byType(KnowledgeTile), findsNWidgets(2), reason: '第 1 条被今日卡片拿走了');
    });

    testWidgets('今日安全知识关掉后，那一条回到推荐里', (WidgetTester tester) async {
      // 列表第 1 条本来是给今日卡片的。今日整块关掉之后它应该回到推荐里，
      // 否则用户关掉一个模块反而**少看到一条内容**。
      await pumpLoggedIn(
        tester,
        _backendWith(_threeItems, homeModules: <String>['recommend']),
      );

      expect(find.byType(KnowledgeTile), findsNWidgets(3), reason: '三条都该在推荐里');
    });

    testWidgets('五个模块全关掉时说明原因并给回去打开的路', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend()
        ..seedSettings('alice', homeModules: <String>[]);

      await pumpLoggedIn(tester, backend);

      expect(find.text('首页模块都被关掉了'), findsOneWidget);
      expect(
        find.textContaining('在「首页布局」里关掉了全部模块'),
        findsOneWidget,
        reason: '必须说清是「你自己关的」，否则用户只会以为这个 App 出了问题',
      );
      expect(find.text('去首页布局打开'), findsOneWidget);

      // 关键：不能只留一片空白，也不能把别的东西显示出来
      expect(find.text('今日安全知识'), findsNothing);
      expect(find.text('安全分类'), findsNothing);
      expect(find.text('AI 安全助手'), findsNothing);
    });

    testWidgets('点「去首页布局打开」进设置页', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend()
        ..seedSettings('alice', homeModules: <String>[]);

      await pumpLoggedIn(tester, backend);

      await tester.tap(find.text('去首页布局打开'));
      await tester.pumpAndSettle();

      expect(find.byType(SettingsHomePage), findsOneWidget);
    });

    testWidgets('设置拉不到时按默认布局显示，而不是整页报错', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend()..settingsErrorStatus = 500;

      await pumpLoggedIn(tester, backend);

      expect(
        find.text('今日安全知识'),
        findsOneWidget,
        reason: '首页的主体是安全知识，设置只是调整它的摆法',
      );
      expect(find.text('安全分类'), findsOneWidget);
      expect(find.textContaining('设置保存失败'), findsNothing, reason: '首页不该替设置页报错');
    });
  });

  group('按关注方向推荐', () {
    testWidgets('关注的领域作为 prefer_categories 发给知识接口', (WidgetTester tester) async {
      await useTallWindow(tester);
      final FakeBackend backend = FakeBackend()
        ..seedAccount('alice', 'hunter2hunter2')
        ..seedSettings('alice', followedCategories: <int>[1, 5]);
      final AuthController auth = backend.authController();
      await auth.login(username: 'alice', password: 'hunter2hunter2');

      await tester.pumpWidget(
        AuthScope(
          controller: auth,
          child: MaterialApp(
            home: HomePage(
              api: backend.api(),
              postApi: backend.postApi(),
              settingsApi: auth.settingsApi,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final Uri sent = backend.requests
          .firstWhere((Uri url) => url.path == '/api/knowledge');
      expect(sent.queryParametersAll['prefer_categories'], <String>['1', '5']);
    });

    testWidgets('没关注任何领域时不带这个参数', (WidgetTester tester) async {
      await useTallWindow(tester);
      final FakeBackend backend = FakeBackend()..seedAccount('alice', 'hunter2hunter2');
      final AuthController auth = backend.authController();
      await auth.login(username: 'alice', password: 'hunter2hunter2');

      await tester.pumpWidget(
        AuthScope(
          controller: auth,
          child: MaterialApp(
            home: HomePage(
              api: backend.api(),
              postApi: backend.postApi(),
              settingsApi: auth.settingsApi,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final Uri sent = backend.requests
          .firstWhere((Uri url) => url.path == '/api/knowledge');
      expect(sent.queryParametersAll.containsKey('prefer_categories'), isFalse);
    });
  });

  group('从别的标签切回首页', () {
    testWidgets('重新取一次设置，改了布局回来就能看到', (WidgetTester tester) async {
      // 底部导航是 IndexedStack，切标签不会重建页面。
      // 没有这个刷新的话，用户去「首页布局」关掉「安全分类」再回来，
      // 看到的还是旧布局，只能靠下拉刷新 —— 而界面上完全看不出这一点。
      final FakeBackend backend = FakeBackend()
        ..seedSettings('alice', homeModules: <String>['daily']);
      await useTallWindow(tester);

      backend.seedAccount('alice', 'hunter2hunter2');
      final AuthController auth = backend.authController();
      await auth.login(username: 'alice', password: 'hunter2hunter2');

      Widget page({required bool active}) => AuthScope(
            controller: auth,
            child: MaterialApp(
              home: HomePage(
                isActive: active,
                api: backend.api(),
                postApi: backend.postApi(),
                settingsApi: auth.settingsApi,
              ),
            ),
          );

      await tester.pumpWidget(page(active: true));
      await tester.pumpAndSettle();
      expect(find.text('安全分类'), findsNothing);

      // 切走再切回来，其间用户在设置页把「安全分类」打开了
      await tester.pumpWidget(page(active: false));
      await tester.pumpAndSettle();
      backend.seedSettings('alice', homeModules: <String>['daily', 'category']);

      await tester.pumpWidget(page(active: true));
      await tester.pumpAndSettle();

      expect(find.text('安全分类'), findsOneWidget);
    });

    testWidgets('切回来时不显示加载态', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend();
      await useTallWindow(tester);

      backend.seedAccount('alice', 'hunter2hunter2');
      final AuthController auth = backend.authController();
      await auth.login(username: 'alice', password: 'hunter2hunter2');

      Widget page({required bool active}) => AuthScope(
            controller: auth,
            child: MaterialApp(
              home: HomePage(
                isActive: active,
                api: backend.api(),
                postApi: backend.postApi(),
                settingsApi: auth.settingsApi,
              ),
            ),
          );

      await tester.pumpWidget(page(active: true));
      await tester.pumpAndSettle();
      expect(find.text('今日安全知识'), findsOneWidget);

      // 让刷新慢下来，才有机会看清「刷新途中」长什么样。
      // 不拖慢的话请求在一帧内就回来了，断言等于没测。
      backend.delay = const Duration(milliseconds: 200);

      await tester.pumpWidget(page(active: false));
      await tester.pump();
      await tester.pumpWidget(page(active: true));
      await tester.pump(const Duration(milliseconds: 50));

      // 内容本来就在，切个标签闪一下转圈比看到旧数据还难受
      expect(find.text('今日安全知识'), findsOneWidget);
      expect(
        find.byType(CircularProgressIndicator),
        findsNothing,
        reason: '刷新途中不该退回加载态',
      );

      // 放行在途的请求。`delay` 在发起时就已被取走，改回 null 不影响
      // 这一次 —— 必须把时钟推过 200ms，否则测试结束时会留下未完成的定时器
      backend.delay = null;
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
    });
  });

  group('通知入口', () {
    testWidgets('点页头通知图标进入通知设置', (WidgetTester tester) async {
      await useTallWindow(tester);
      final FakeBackend backend = FakeBackend()..seedAccount('alice', 'hunter2hunter2');
      final AuthController auth = backend.authController();
      await auth.login(username: 'alice', password: 'hunter2hunter2');

      await tester.pumpWidget(
        AuthScope(
          controller: auth,
          child: MaterialApp(
            home: HomePage(
              api: backend.api(),
              postApi: backend.postApi(),
              settingsApi: auth.settingsApi,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('通知设置'));
      await tester.pumpAndSettle();

      expect(find.byType(SettingsNotifyPage), findsOneWidget);
    });

    testWidgets('未登录时先推登录页，而不是跳进一个只会报 401 的页面', (WidgetTester tester) async {
      await useTallWindow(tester);
      final FakeBackend backend = FakeBackend();

      await tester.pumpWidget(
        AuthScope(
          controller: backend.authController(),
          child: MaterialApp(
            home: HomePage(api: backend.api(), postApi: backend.postApi()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('通知设置'));
      await tester.pumpAndSettle();

      expect(find.byType(LoginPage), findsOneWidget);
      expect(find.byType(SettingsNotifyPage), findsNothing);
    });
  });
}
