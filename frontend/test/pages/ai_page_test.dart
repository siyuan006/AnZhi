import 'package:anzhi/models/ai_answer.dart';
import 'package:anzhi/pages/ai_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_backend.dart';

/// 安知 —— AI 问答页测试（阶段 8）
///
/// 重点不在「界面好不好看」，而在几条不能退化的行为：
///  · 等待期间必须让用户看到「正在思考」，而不是一个空白气泡
///  · 失败必须显示后端给的中文说明，绝不能伪造一条 AI 回答
///  · 等待期间不能重复发送
void main() {
  /// 默认 800x600 的测试窗口放不下整页内容，
  /// 折叠线以下的组件不会被构建，导致「明明存在却找不到」
  Future<void> useTallWindow(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  Future<void> pumpPage(WidgetTester tester, FakeBackend backend) async {
    await useTallWindow(tester);
    await tester.pumpWidget(
      MaterialApp(home: AiPage(api: backend.chatApi())),
    );
    await tester.pumpAndSettle();
  }

  group('空状态', () {
    testWidgets('未提问时展示引导与安全声明', (WidgetTester tester) async {
      await pumpPage(tester, FakeBackend());

      expect(find.text('有安全方面的问题，随时问我'), findsOneWidget);
      expect(find.text('宿舍发生火灾怎么办？'), findsOneWidget);
      // 紧急情况下不能让用户干等 App 回答
      expect(find.textContaining('119'), findsOneWidget);
    });

    testWidgets('没有对话时清空按钮不可用', (WidgetTester tester) async {
      await pumpPage(tester, FakeBackend());

      final IconButton button = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.delete_outline_rounded),
      );
      expect(button.onPressed, isNull);
    });
  });

  group('提问与回答', () {
    testWidgets('点击推荐问题后展示 AI 回答的正文、步骤与警告', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend();
      await pumpPage(tester, backend);

      await tester.tap(find.text('宿舍发生火灾怎么办？'));
      await tester.pumpAndSettle();

      expect(find.text('先确保自身安全，再判断是否能够撤离。'), findsOneWidget);
      expect(find.text('具体步骤'), findsOneWidget);
      expect(find.text('立即报警'), findsOneWidget);
      expect(find.text('如已有人受伤，请立即拨打 120。'), findsOneWidget);
      // 高风险回答必须带风险标识
      expect(find.text('高风险'), findsOneWidget);
    });

    testWidgets('输入框提问同样会发给后端', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend();
      await pumpPage(tester, backend);

      await tester.enterText(find.byType(TextField), '  插座冒烟了怎么办？  ');
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pumpAndSettle();

      // 首尾空格应在客户端就被去掉，不要把无意义的空白发给模型
      expect(backend.chatRequests.single['message'], '插座冒烟了怎么办？');
      // 用户的问题也要显示在对话里
      expect(find.text('插座冒烟了怎么办？'), findsWidgets);
    });

    testWidgets('空白输入不发送请求', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend();
      await pumpPage(tester, backend);

      await tester.enterText(find.byType(TextField), '    ');
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pumpAndSettle();

      expect(backend.chatRequests, isEmpty);
    });

    testWidgets('回答按顺序累加，用户问题在上、AI 回答在下', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend();
      await pumpPage(tester, backend);

      await tester.tap(find.text('宿舍发生火灾怎么办？'));
      await tester.pumpAndSettle();

      final double questionY = tester.getTopLeft(find.text('宿舍发生火灾怎么办？')).dy;
      final double answerY =
          tester.getTopLeft(find.text('先确保自身安全，再判断是否能够撤离。')).dy;
      expect(questionY, lessThan(answerY));
    });
  });

  group('等待状态', () {
    testWidgets('等待回答时展示「正在思考」气泡', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend()
        ..delay = const Duration(milliseconds: 500);
      await pumpPage(tester, backend);

      await tester.tap(find.text('宿舍发生火灾怎么办？'));
      await tester.pump(); // 送出请求，此时回答还没回来

      expect(find.text('正在思考…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      // 尚未拿到回答，不能提前显示任何正文
      expect(find.text('先确保自身安全，再判断是否能够撤离。'), findsNothing);

      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      expect(find.text('正在思考…'), findsNothing);
      expect(find.text('先确保自身安全，再判断是否能够撤离。'), findsOneWidget);
    });

    testWidgets('等待期间按钮与回车都不再触发请求', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend()
        ..delay = const Duration(milliseconds: 500);
      await pumpPage(tester, backend);

      await tester.tap(find.text('宿舍发生火灾怎么办？'));
      await tester.pump();

      final FilledButton button =
          tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);

      // 输入框还开着，回车也不能穿透过去再发一次
      await tester.enterText(find.byType(TextField), '再问一次');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();

      expect(backend.chatRequests, hasLength(1));

      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
    });

    testWidgets('等待期间清空对话按钮不可用', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend()
        ..delay = const Duration(milliseconds: 500);
      await pumpPage(tester, backend);

      await tester.tap(find.text('宿舍发生火灾怎么办？'));
      await tester.pump();

      final IconButton button = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.delete_outline_rounded),
      );
      expect(button.onPressed, isNull);

      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
    });
  });

  group('失败处理', () {
    testWidgets('未配置 Key 时显示后端返回的中文说明，不伪造回答', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend()
        ..chatErrorStatus = 503
        ..chatErrorMessage = 'AI 服务未配置，请联系管理员在后端 .env 中设置 DEEPSEEK_API_KEY';
      await pumpPage(tester, backend);

      await tester.tap(find.text('宿舍发生火灾怎么办？'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('DEEPSEEK_API_KEY'),
        findsOneWidget,
      );
      // 关键：失败时不能出现任何看似 AI 回答的内容
      expect(find.text('具体步骤'), findsNothing);
      expect(find.text('高风险'), findsNothing);
    });

    testWidgets('连不上后端时给出可读提示', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend()..offline = true;
      await pumpPage(tester, backend);

      await tester.tap(find.text('宿舍发生火灾怎么办？'));
      await tester.pumpAndSettle();

      expect(find.textContaining('无法连接到服务器'), findsOneWidget);
    });

    testWidgets('失败后仍可继续提问', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend()..chatErrorStatus = 503;
      await pumpPage(tester, backend);

      await tester.tap(find.text('宿舍发生火灾怎么办？'));
      await tester.pumpAndSettle();

      // 恢复后重试应当能拿到正常回答
      // （此时推荐问题已被对话列表取代，改为从输入框提问）
      backend.chatErrorStatus = null;
      await tester.enterText(find.byType(TextField), '地震时在室内应该躲哪里？');
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pumpAndSettle();

      expect(find.text('先确保自身安全，再判断是否能够撤离。'), findsOneWidget);
    });
  });

  group('清空对话', () {
    testWidgets('清空后回到空状态', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend();
      await pumpPage(tester, backend);

      await tester.tap(find.text('宿舍发生火灾怎么办？'));
      await tester.pumpAndSettle();
      expect(find.text('有安全方面的问题，随时问我'), findsNothing);

      await tester.tap(find.byIcon(Icons.delete_outline_rounded));
      await tester.pumpAndSettle();

      expect(find.text('有安全方面的问题，随时问我'), findsOneWidget);
      expect(find.text('先确保自身安全，再判断是否能够撤离。'), findsNothing);
    });

    testWidgets('清空只影响界面，不会重新请求后端', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend();
      await pumpPage(tester, backend);

      await tester.tap(find.text('宿舍发生火灾怎么办？'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.delete_outline_rounded));
      await tester.pumpAndSettle();

      expect(backend.chatRequests, hasLength(1));
    });
  });

  group('消息模型', () {
    test('错误消息与 AI 回答必须可区分', () {
      final ChatMessage error = ChatMessage.error('请求超时');
      expect(error.isError, isTrue);
      expect(error.answer, isNull);
      expect(error.isUser, isFalse);

      final ChatMessage assistant = ChatMessage.assistant(
        const AiAnswer(question: 'q', answer: 'a'),
      );
      expect(assistant.isError, isFalse);
      expect(assistant.answer, isNotNull);
    });
  });
}
