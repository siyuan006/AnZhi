import 'package:anzhi/core/auth_controller.dart';
import 'package:anzhi/models/post_item.dart';
import 'package:anzhi/pages/post_detail_page.dart';
import 'package:anzhi/services/post_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_backend.dart';

/// 安知 —— 帖子详情页测试（阶段 12a 正文，12b 评论）
///
/// 重点：
///   · 从列表带过来的 preview 要先把页头画出来（不能整页转圈）
///   · 正文来自详情接口，不是列表的摘要
///   · 帖子不存在时给可读的 404，而不是空白页
///   · 评论能用，但**未登录时不能假装能用**
///   · 点赞如实标注阶段，不是点了没反应
void main() {
  Future<AuthController> pumpDetail(
    WidgetTester tester,
    FakeBackend backend, {
    int postId = 1,
    PostItem? preview,
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
          home: PostDetailPage(
            postId: postId,
            preview: preview,
            // 用 authController 的客户端：发评论要带上它的 token
            api: PostApi(client: auth.apiClient),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return auth;
  }

  group('正文', () {
    testWidgets('显示标题与正文全文', (WidgetTester tester) async {
      await pumpDetail(tester, FakeBackend());

      expect(find.text('宿舍用电的几点提醒'), findsOneWidget);
      expect(
        find.textContaining('电线过热是宿舍火灾最常见的原因'),
        findsOneWidget,
        reason: '正文来自详情接口，不是列表的摘要',
      );
    });

    testWidgets('从列表带 preview 进来时，页头立刻可见', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend()
        ..delay = const Duration(seconds: 1);

      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: PostDetailPage(
            postId: 1,
            preview: const PostItem(id: 1, title: '宿舍用电的几点提醒', summary: '摘要'),
            api: backend.postApi(),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('宿舍用电的几点提醒'), findsOneWidget, reason: '标题应已画出');
      expect(find.text('正在加载正文…'), findsOneWidget, reason: '正文位置显示加载中');

      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(find.textContaining('电线过热'), findsOneWidget);
    });

    testWidgets('没有 preview 且还在加载时显示加载中', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend()
        ..delay = const Duration(seconds: 1);

      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(home: PostDetailPage(postId: 1, api: backend.postApi())),
      );
      await tester.pump();

      expect(find.text('正在加载帖子…'), findsOneWidget);

      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(find.text('宿舍用电的几点提醒'), findsOneWidget);
    });

    testWidgets('显示作者、分类与互动数', (WidgetTester tester) async {
      await pumpDetail(tester, FakeBackend());

      expect(find.text('小艾'), findsOneWidget);
      expect(find.text('用电安全'), findsOneWidget);
      expect(find.text('3'), findsOneWidget, reason: '点赞数');
      expect(find.text('1'), findsOneWidget, reason: '评论数');
    });

    testWidgets('没有分类的帖子不显示分类标签', (WidgetTester tester) async {
      await pumpDetail(tester, FakeBackend(), postId: 2);

      expect(find.text('遇到诈骗电话我是这么处理的'), findsOneWidget);
      expect(find.text('用电安全'), findsNothing);
    });

    testWidgets('帖子不存在时给可读的 404 与重试按钮', (WidgetTester tester) async {
      await pumpDetail(tester, FakeBackend(), postId: 999999);

      expect(find.text('帖子不存在或已删除'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '重试'), findsOneWidget);
    });

    testWidgets('点赞如实标注阶段 12c', (WidgetTester tester) async {
      await pumpDetail(tester, FakeBackend());

      await tester.tap(find.byTooltip('点赞'));
      await tester.pumpAndSettle();

      expect(find.textContaining('阶段 12c'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('评论', () {
    testWidgets('显示评论列表', (WidgetTester tester) async {
      await pumpDetail(tester, FakeBackend());

      expect(find.textContaining('充电器长期插着也会发热'), findsOneWidget);
      expect(find.text('小周'), findsOneWidget);
      expect(find.text('评论 1'), findsOneWidget);
    });

    testWidgets('没有评论时如实说明，而不是留白', (WidgetTester tester) async {
      await pumpDetail(tester, FakeBackend(), postId: 2);

      expect(find.textContaining('还没有人评论'), findsOneWidget);
    });

    testWidgets('评论拉不到时只说这一块，正文照常可读', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend()
        ..commentReadStatus = 500
        ..commentReadError = '评论加载失败';

      await pumpDetail(tester, backend);

      expect(find.text('评论加载失败'), findsOneWidget);
      expect(
        find.textContaining('还没有人评论'),
        findsNothing,
        reason: '拉不到和确实没有是两回事',
      );
      expect(
        find.textContaining('电线过热是宿舍火灾最常见的原因'),
        findsOneWidget,
        reason: '评论挂了不该把正文一起吃掉',
      );
    });

    testWidgets('未登录时输入框不可用，并说明原因', (WidgetTester tester) async {
      await pumpDetail(tester, FakeBackend());

      expect(find.text('登录后可以发表评论'), findsOneWidget);
      expect(find.text('登录后可以参与讨论'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, '发表')).onPressed,
        isNull,
        reason: '按钮不能是可点的 —— 点了才报错是更差的体验',
      );
    });

    testWidgets('登录后能发评论，发完立刻出现在列表里', (WidgetTester tester) async {
      await pumpDetail(tester, FakeBackend(), loggedIn: true);

      await tester.enterText(find.byType(TextField), '我也遇到过');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.tap(find.widgetWithText(FilledButton, '发表'));
      await tester.pumpAndSettle();

      expect(find.text('我也遇到过'), findsOneWidget);
      expect(find.text('评论 2'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
        reason: '发出去之后输入框要清空',
      );
    });

    testWidgets('发评论失败时提示原因，且不清空已输入的内容', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend()
        ..commentPostStatus = 500
        ..commentPostError = '评论发表失败';

      await pumpDetail(tester, backend, loggedIn: true);

      await tester.enterText(find.byType(TextField), '写了好一会儿的一段话');
      await tester.tap(find.widgetWithText(FilledButton, '发表'));
      await tester.pumpAndSettle();

      expect(find.text('评论发表失败'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '写了好一会儿的一段话',
        reason: '发失败还把用户打的字清掉，是最让人恼火的一种做法',
      );
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('空内容点发表不会发出请求', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend();
      await pumpDetail(tester, backend, loggedIn: true);

      await tester.enterText(find.byType(TextField), '   ');
      await tester.tap(find.widgetWithText(FilledButton, '发表'));
      await tester.pumpAndSettle();

      expect(
        backend.requests.where(
          (Uri url) => url.path.endsWith('/comments'),
        ).length,
        1,
        reason: '只有页面加载时那一次读，不该有 POST',
      );
      expect(find.text('评论 1'), findsOneWidget);
    });
  });
}
