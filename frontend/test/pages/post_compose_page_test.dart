import 'package:anzhi/core/auth_controller.dart';
import 'package:anzhi/models/post_item.dart';
import 'package:anzhi/pages/post_compose_page.dart';
import 'package:anzhi/services/post_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_backend.dart';

/// 安知 —— 发帖页测试（阶段 12d）
///
/// 重点：
///   · 空标题 / 空正文时发不出去，**全空格也算空**
///   · 失败时**不清空用户已经打的字** —— 让人重打一遍是最气人的
///   · 选中的分类要真的传进请求体，而不是界面上选了、发出去是 null
///   · 成功后把新帖子带回去，让上一页据此刷新
void main() {
  Future<void> pumpCompose(
    WidgetTester tester,
    FakeBackend backend, {
    bool loggedIn = true,
    void Function(PostItem?)? onPopped,
  }) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final AuthController auth = backend.authController();
    if (loggedIn) {
      backend.seedAccount('xiaoming', 'hunter2hunter2', nickname: '小明');
      await auth.login(username: 'xiaoming', password: 'hunter2hunter2');
    }

    await tester.pumpWidget(
      AuthScope(
        controller: auth,
        child: MaterialApp(
          home: Builder(
            builder: (BuildContext context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    final PostItem? created = await Navigator.of(context)
                        .push<PostItem>(
                      MaterialPageRoute<PostItem>(
                        builder: (_) => PostComposePage(
                          api: PostApi(client: auth.apiClient),
                        ),
                      ),
                    );
                    onPopped?.call(created);
                  },
                  child: const Text('去打开发帖页'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('去打开发帖页'));
    await tester.pumpAndSettle();
  }

  Future<void> fill(
    WidgetTester tester, {
    String title = '宿舍用电提醒',
    String content = '不要在一个插排上同时接大功率电器。',
  }) async {
    await tester.enterText(find.widgetWithText(TextField, '标题'), title);
    await tester.enterText(find.widgetWithText(TextField, '正文'), content);
    await tester.pumpAndSettle();
  }

  Finder publishButton() => find.widgetWithText(TextButton, '发布');

  bool publishEnabled(WidgetTester tester) =>
      tester.widget<TextButton>(publishButton()).onPressed != null;

  group('表单', () {
    testWidgets('显示标题、正文与分类选择', (WidgetTester tester) async {
      await pumpCompose(tester, FakeBackend());

      expect(find.text('发布帖子'), findsOneWidget, reason: '标题栏');
      expect(find.widgetWithText(TextField, '标题'), findsOneWidget);
      expect(find.widgetWithText(TextField, '正文'), findsOneWidget);
      expect(find.text('分类（可不选）'), findsOneWidget);
      expect(find.text('消防安全'), findsOneWidget, reason: '分类选项');
    });

    testWidgets('刚进来时发不出去', (WidgetTester tester) async {
      await pumpCompose(tester, FakeBackend());

      expect(publishEnabled(tester), isFalse);
    });

    testWidgets('只填了标题也发不出去', (WidgetTester tester) async {
      await pumpCompose(tester, FakeBackend());

      await tester.enterText(
        find.widgetWithText(TextField, '标题'),
        '只有标题',
      );
      await tester.pumpAndSettle();

      expect(publishEnabled(tester), isFalse);
    });

    testWidgets('标题与正文都填了才能发', (WidgetTester tester) async {
      await pumpCompose(tester, FakeBackend());

      await fill(tester);

      expect(publishEnabled(tester), isTrue);
    });

    testWidgets('全空格的标题不算填了', (WidgetTester tester) async {
      await pumpCompose(tester, FakeBackend());

      await fill(tester, title: '   ');

      expect(
        publishEnabled(tester),
        isFalse,
        reason: '只打空格等于没写，放过去的话服务端会 422',
      );
    });

    testWidgets('全空格的正文不算填了', (WidgetTester tester) async {
      await pumpCompose(tester, FakeBackend());

      await fill(tester, content: '\n  \n');

      expect(publishEnabled(tester), isFalse);
    });

    testWidgets('未登录时说明要先登录，且不显示表单', (WidgetTester tester) async {
      await pumpCompose(tester, FakeBackend(), loggedIn: false);

      expect(find.text('登录后才能发布帖子'), findsOneWidget);
      expect(find.widgetWithText(TextField, '标题'), findsNothing);
    });
  });

  group('提交', () {
    testWidgets('成功后把新帖子带回上一页', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend();
      PostItem? popped;

      await pumpCompose(tester, backend, onPopped: (PostItem? p) => popped = p);
      await fill(tester);
      await tester.tap(publishButton());
      await tester.pumpAndSettle();

      expect(popped, isNotNull, reason: '要 pop 出新帖子，上一页才知道刷新');
      expect(popped!.title, '宿舍用电提醒');
      expect(popped!.id, greaterThan(0));
    });

    testWidgets('提交后返回，页面不再停留在发帖页', (WidgetTester tester) async {
      await pumpCompose(tester, FakeBackend());
      await fill(tester);
      await tester.tap(publishButton());
      await tester.pumpAndSettle();

      expect(find.byType(PostComposePage), findsNothing);
    });

    testWidgets('首尾空白由服务端去掉，客户端原样发', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend();

      await pumpCompose(tester, backend);
      await fill(tester, title: '  宿舍用电提醒  ');
      await tester.tap(publishButton());
      await tester.pumpAndSettle();

      expect(backend.postCreateRequests.single['title'], '  宿舍用电提醒  ');
      // 压成一行、去掉首尾是服务端的活（后端那边有专门的用例钉着）。
      // 客户端只管把用户打的字如实发出去，不做第二套规则 ——
      // 两边各写一套的话，迟早会出现「本地放过、服务端拒绝」。
      expect(backend.posts.first['title'], '宿舍用电提醒');
    });

    testWidgets('没选分类时 category_id 是 null', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend();

      await pumpCompose(tester, backend);
      await fill(tester);
      await tester.tap(publishButton());
      await tester.pumpAndSettle();

      expect(backend.postCreateRequests.single['category_id'], isNull);
    });

    testWidgets('选中的分类真的传进了请求体', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend();

      await pumpCompose(tester, backend);
      await fill(tester);
      await tester.tap(find.text('消防安全'));
      await tester.pumpAndSettle();
      await tester.tap(publishButton());
      await tester.pumpAndSettle();

      expect(
        backend.postCreateRequests.single['category_id'],
        1,
        reason: '界面上选了，发出去却是 null 的话，帖子会掉进「无分类」',
      );
    });

    testWidgets('再点一下取消选择，回到不选分类', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend();

      await pumpCompose(tester, backend);
      await fill(tester);
      await tester.tap(find.text('消防安全'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('消防安全'));
      await tester.pumpAndSettle();
      await tester.tap(publishButton());
      await tester.pumpAndSettle();

      expect(backend.postCreateRequests.single['category_id'], isNull);
    });

    testWidgets('发出去的新帖子会出现在社区列表里', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend();

      await pumpCompose(tester, backend);
      await fill(tester, title: '刚发的这一条');
      await tester.tap(publishButton());
      await tester.pumpAndSettle();

      expect(backend.posts.first['title'], '刚发的这一条');
    });
  });

  group('失败', () {
    testWidgets('失败时提示原因，并留在发帖页', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend()
        ..postCreateStatus = 500
        ..postCreateError = '服务器开小差了';

      await pumpCompose(tester, backend);
      await fill(tester);
      await tester.tap(publishButton());
      await tester.pumpAndSettle();

      expect(find.text('服务器开小差了'), findsOneWidget);
      expect(find.byType(PostComposePage), findsOneWidget);
    });

    testWidgets('失败时不清空已经打的字', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend()..postCreateStatus = 500;

      await pumpCompose(tester, backend);
      await fill(tester, title: '辛苦打的标题', content: '辛苦打的正文');
      await tester.tap(publishButton());
      await tester.pumpAndSettle();

      expect(
        find.text('辛苦打的标题'),
        findsOneWidget,
        reason: '发失败了还把人家打的字清掉，是最气人的',
      );
      expect(find.text('辛苦打的正文'), findsOneWidget);
    });

    testWidgets('失败之后还能再发一次', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend()..postCreateStatus = 500;

      await pumpCompose(tester, backend);
      await fill(tester);
      await tester.tap(publishButton());
      await tester.pumpAndSettle();

      expect(publishEnabled(tester), isTrue, reason: '按钮不能卡在禁用状态');
    });
  });
}
