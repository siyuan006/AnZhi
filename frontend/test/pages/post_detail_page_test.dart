import 'package:anzhi/models/post_item.dart';
import 'package:anzhi/pages/post_detail_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_backend.dart';

/// 安知 —— 帖子详情页测试（阶段 12a）
///
/// 重点：
///   · 从列表带过来的 preview 要先把页头画出来（不能整页转圈）
///   · 正文来自详情接口，不是列表的摘要
///   · 帖子不存在时给可读的 404，而不是空白页
///   · 点赞与评论如实标注阶段，不是点了没反应
void main() {
  Future<void> pumpDetail(
    WidgetTester tester,
    FakeBackend backend, {
    int postId = 1,
    PostItem? preview,
  }) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: PostDetailPage(
          postId: postId,
          preview: preview,
          api: backend.postApi(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

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
    // 用户点进来看到的是自己点的那条，而不是一整页的转圈
    final FakeBackend backend = FakeBackend()..delay = const Duration(seconds: 1);

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
    final FakeBackend backend = FakeBackend()..delay = const Duration(seconds: 1);

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

  testWidgets('评论与点赞如实标注阶段', (WidgetTester tester) async {
    await pumpDetail(tester, FakeBackend());

    // 评论区不能只留白 —— 用户会以为加载失败
    expect(find.textContaining('阶段 12b'), findsOneWidget);

    await tester.tap(find.byTooltip('点赞'));
    await tester.pumpAndSettle();
    expect(find.textContaining('阶段 12c'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });
}
