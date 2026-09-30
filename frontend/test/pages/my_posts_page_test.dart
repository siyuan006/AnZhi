import 'package:anzhi/core/auth_controller.dart';
import 'package:anzhi/pages/my_posts_page.dart';
import 'package:anzhi/pages/post_detail_page.dart';
import 'package:anzhi/services/post_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_backend.dart';

/// 安知 —— 我的帖子测试（阶段 12d）
///
/// 重点：
///   · 未登录如实说「请先登录」，而不是「还没有发过帖子」
///     —— 不是没有，是不知道你是谁
///   · **只列自己的帖子**（假后端里 A 看不到 B 的，这条必须成立）
///   · 删除要先问一句，问清楚删的是哪一条
///   · 删失败时那一行不能消失 —— 界面说删了、服务端说没删，是最糟的
void main() {
  Future<void> pumpMyPosts(
    WidgetTester tester,
    FakeBackend backend, {
    bool loggedIn = true,
    void Function()? afterLogin,
  }) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final AuthController auth = backend.authController();
    if (loggedIn) {
      backend.seedAccount('alice', 'hunter2hunter2', nickname: '小艾');
      await auth.login(username: 'alice', password: 'hunter2hunter2');
    }

    // `errorStatus` 之类的开关要等登录之后再打开 ——
    // 提前打开的话登录请求自己就先挂了，页面会显示「请先登录」，
    // 于是「拉不到帖子」这件事根本走不到，测的就成了另一回事
    afterLogin?.call();

    await tester.pumpWidget(
      AuthScope(
        controller: auth,
        child: MaterialApp(
          // 用 authController 的客户端：本页所有接口都要登录
          home: MyPostsPage(api: PostApi(client: auth.apiClient)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('加载成功', () {
    testWidgets('只列出自己发的帖子', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend();

      await pumpMyPosts(tester, backend);

      expect(find.text('宿舍用电的几点提醒'), findsOneWidget, reason: 'alice 发的');
      expect(
        find.text('遇到诈骗电话我是这么处理的'),
        findsNothing,
        reason: 'bob 发的，不该出现在我的帖子里',
      );
    });

    testWidgets('显示总数', (WidgetTester tester) async {
      await pumpMyPosts(tester, FakeBackend());

      expect(find.text('共 1 条帖子'), findsOneWidget);
    });

    testWidgets('没有分类的帖子不画分类标签', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend();
      backend.seedNoPosts();
      backend.seedPost(title: '没有分类的一条', owner: 'alice');

      await pumpMyPosts(tester, backend);

      expect(find.text('没有分类的一条'), findsOneWidget);
      expect(find.text('消防安全'), findsNothing);
    });

    testWidgets('一条都没有时如实说明', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend()..seedNoPosts();

      await pumpMyPosts(tester, backend);

      expect(find.text('还没有发过帖子'), findsOneWidget);
    });

    testWidgets('点一条进详情页', (WidgetTester tester) async {
      await pumpMyPosts(tester, FakeBackend());

      await tester.tap(find.text('宿舍用电的几点提醒'));
      await tester.pumpAndSettle();

      expect(find.byType(PostDetailPage), findsOneWidget);
    });

    testWidgets('超过一页时可以加载更多', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend();
      backend.seedNoPosts();
      for (int i = 1; i <= 25; i++) {
        backend.seedPost(title: '我的第 $i 条', owner: 'alice');
      }

      await pumpMyPosts(tester, backend);

      // 一屏放不下 20 条，「加载更多」在下面 —— 列表是懒构建的，
      // 不滚过去它根本不存在，`find` 自然也找不到
      await tester.scrollUntilVisible(find.text('加载更多'), 400);
      await tester.tap(find.text('加载更多'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('共 25 条帖子'), 400);
      expect(find.text('加载更多'), findsNothing);
    });
  });

  group('未登录', () {
    testWidgets('如实说请先登录，而不是「还没有发过帖子」', (WidgetTester tester) async {
      await pumpMyPosts(tester, FakeBackend(), loggedIn: false);

      expect(find.text('请先登录'), findsOneWidget);
      expect(
        find.text('还没有发过帖子'),
        findsNothing,
        reason: '不是没有，是不知道你是谁 —— 这两句不能混',
      );
    });

    testWidgets('给一个去登录的入口', (WidgetTester tester) async {
      await pumpMyPosts(tester, FakeBackend(), loggedIn: false);

      expect(find.text('去登录'), findsOneWidget);
    });

    testWidgets('未登录时不显示发帖按钮', (WidgetTester tester) async {
      await pumpMyPosts(tester, FakeBackend(), loggedIn: false);

      expect(find.byType(FloatingActionButton), findsNothing);
    });
  });

  group('加载失败', () {
    testWidgets('说明原因并给重试', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend();

      await pumpMyPosts(
        tester,
        backend,
        afterLogin: () => backend.errorStatus = 500,
      );

      expect(find.text('重试'), findsOneWidget);
      expect(
        find.text('还没有发过帖子'),
        findsNothing,
        reason: '拉不到和「确实没有」必须分开说，否则用户以为帖子丢了',
      );
    });

    testWidgets('重试能重新拉到', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend();

      await pumpMyPosts(
        tester,
        backend,
        afterLogin: () => backend.errorStatus = 500,
      );
      backend.errorStatus = null;
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();

      expect(find.text('宿舍用电的几点提醒'), findsOneWidget);
    });
  });

  group('删除', () {
    Future<void> tapDelete(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.delete_outline_rounded).first);
      await tester.pumpAndSettle();
    }

    testWidgets('先弹确认框，且说清楚删的是哪一条', (WidgetTester tester) async {
      await pumpMyPosts(tester, FakeBackend());

      await tapDelete(tester);

      expect(find.text('删除这条帖子？'), findsOneWidget);
      expect(
        find.textContaining('宿舍用电的几点提醒'),
        findsWidgets,
        reason: '只写「确定删除吗」等于让用户凭记忆赌一把',
      );
    });

    testWidgets('取消就什么都不做', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend();

      await pumpMyPosts(tester, backend);
      await tapDelete(tester);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(find.text('宿舍用电的几点提醒'), findsOneWidget);
      expect(backend.posts.length, 2, reason: '后端一条都不该少');
    });

    testWidgets('确认后那一行消失、总数减一', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend();

      await pumpMyPosts(tester, backend);
      await tapDelete(tester);
      await tester.tap(find.widgetWithText(TextButton, '删除'));
      await tester.pumpAndSettle();

      expect(find.text('宿舍用电的几点提醒'), findsNothing);
      expect(find.text('还没有发过帖子'), findsOneWidget);
      expect(backend.posts.length, 1, reason: '后端也确实删掉了');
    });

    testWidgets('删完给一句反馈', (WidgetTester tester) async {
      await pumpMyPosts(tester, FakeBackend());

      await tapDelete(tester);
      await tester.tap(find.widgetWithText(TextButton, '删除'));
      await tester.pumpAndSettle();

      expect(find.text('已删除'), findsOneWidget);
    });

    testWidgets('删失败时那一行还在，并说明原因', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend()
        ..postDeleteStatus = 500
        ..postDeleteError = '删除失败，请稍后再试';

      await pumpMyPosts(tester, backend);
      await tapDelete(tester);
      await tester.tap(find.widgetWithText(TextButton, '删除'));
      await tester.pumpAndSettle();

      expect(
        find.text('宿舍用电的几点提醒'),
        findsOneWidget,
        reason: '界面说删了、服务端说没删，是最糟的一种不一致',
      );
      expect(find.text('删除失败，请稍后再试'), findsOneWidget);
    });
  });
}
