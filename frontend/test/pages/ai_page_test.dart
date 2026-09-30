import 'package:anzhi/core/app_constants.dart';
import 'package:anzhi/models/ai_answer.dart';
import 'package:anzhi/pages/ai_page.dart';
import 'package:anzhi/pages/knowledge_detail_page.dart';
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
      MaterialApp(
        home: AiPage(
          api: backend.chatApi(),
          // 引用要能点进详情页，而详情页会去发真实请求 ——
          // 不注入的话测试里跑的是失败分支
          knowledgeApi: backend.api(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 一条真实存在的知识卡片（id 与 [FakeBackend.defaultItems] 对应），
  /// 用它当引用才能验证「点开读到的是知识库里的原文」
  const Map<String, dynamic> referenceJson = <String, dynamic>{
    'id': 1,
    'title': '宿舍发生火灾如何正确逃生',
    'summary': '低姿撤离、不乘电梯、不贪恋财物。',
    'category_id': 1,
    'risk_level': 'high',
  };

  FakeBackend backendWithReferences() {
    final FakeBackend backend = FakeBackend();
    backend.chatAnswer = <String, dynamic>{
      ...backend.chatAnswer,
      // 与引用的分类特意错开：模型自己判的分类和知识库里那条的分类
      // 本来就是两回事，混在一起断言会分不清看到的是哪一个
      'category': '校园安全',
      'sources': <String>['《消防法》'],
      'references': <Map<String, dynamic>>[referenceJson],
    };
    return backend;
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

  group('相关知识引用（阶段 14）', () {
    testWidgets('回答带引用时展示卡片标题与分类', (WidgetTester tester) async {
      final FakeBackend backend = backendWithReferences();
      await pumpPage(tester, backend);

      await tester.tap(find.text('宿舍发生火灾怎么办？'));
      await tester.pumpAndSettle();

      expect(find.text('相关知识'), findsOneWidget);
      expect(find.text('宿舍发生火灾如何正确逃生'), findsOneWidget);
      expect(find.text('消防安全'), findsOneWidget);
    });

    testWidgets('没有引用时不显示「相关知识」这一栏', (WidgetTester tester) async {
      // 知识库里没有相关内容是正常状态，不该留一个空标题让用户以为出了问题
      final FakeBackend backend = FakeBackend();
      await pumpPage(tester, backend);

      await tester.tap(find.text('宿舍发生火灾怎么办？'));
      await tester.pumpAndSettle();

      expect(find.text('先确保自身安全，再判断是否能够撤离。'), findsOneWidget);
      expect(find.text('相关知识'), findsNothing);
      expect(find.text('参考来源'), findsNothing);
    });

    testWidgets('点开引用进入知识详情页，读到的是知识库原文', (WidgetTester tester) async {
      final FakeBackend backend = backendWithReferences();
      await pumpPage(tester, backend);

      await tester.tap(find.text('宿舍发生火灾怎么办？'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('宿舍发生火灾如何正确逃生'));
      await tester.pumpAndSettle();

      expect(find.byType(KnowledgeDetailPage), findsOneWidget);
      // 详情页真的按 id 取到了那一条，而不是把列表里的第一条硬塞进来
      expect(
        backend.requests.any((Uri url) => url.path == '/api/knowledge/1'),
        isTrue,
        reason: '应当按引用给出的 id 请求详情',
      );
    });

    testWidgets('模型自己写的依据与知识库引用分开展示', (WidgetTester tester) async {
      // 两者可信度不同：一个是模型说的，一个是能点开读原文的。
      // 混成一个列表会让用户以为「模型说的」也有据可查。
      final FakeBackend backend = backendWithReferences();
      await pumpPage(tester, backend);

      await tester.tap(find.text('宿舍发生火灾怎么办？'));
      await tester.pumpAndSettle();

      expect(find.text('相关知识'), findsOneWidget);
      expect(find.text('参考来源'), findsOneWidget);
      expect(find.text('· 《消防法》'), findsOneWidget);
    });
  });

  group('引用模型', () {
    test('解析后端返回的 references', () {
      final AiAnswer answer = AiAnswer.fromJson(<String, dynamic>{
        'question': 'q',
        'answer': 'a',
        'references': <Map<String, dynamic>>[referenceJson],
      });

      expect(answer.references, hasLength(1));
      expect(answer.references.single.id, 1);
      expect(answer.references.single.title, '宿舍发生火灾如何正确逃生');
      expect(answer.references.single.categoryId, 1);
      expect(answer.references.single.categoryName, '消防安全');
      expect(answer.references.single.riskLevel, RiskLevel.high);
    });

    test('字段缺失或结构不对时降级，而不是整条回答解析失败', () {
      final AiAnswer answer = AiAnswer.fromJson(<String, dynamic>{
        'question': 'q',
        'answer': 'a',
        'references': <dynamic>[
          '不是对象',
          <String, dynamic>{'id': 9},
        ],
      });

      // 结构不对的条目被跳过，能用的那条仍然保留
      expect(answer.references, hasLength(1));
      expect(answer.references.single.id, 9);
      expect(answer.references.single.title, '');
      expect(answer.references.single.categoryId, 0);
      expect(answer.references.single.categoryName, '未分类');
    });

    test('后端不返回 references 时为空列表，不是 null', () {
      final AiAnswer answer = AiAnswer.fromJson(<String, dynamic>{
        'question': 'q',
        'answer': 'a',
      });

      expect(answer.references, isEmpty);
    });

    test('出处可以转成详情页的预览数据', () {
      final KnowledgeReference reference =
          KnowledgeReference.fromJson(referenceJson);
      final preview = reference.toPreview();

      expect(preview.id, 1);
      expect(preview.title, '宿舍发生火灾如何正确逃生');
      expect(preview.summary, '低姿撤离、不乘电梯、不贪恋财物。');
      // 带上分类与风险等级，页头才不会先空着再跳一下
      expect(preview.categoryName, '消防安全');
      expect(preview.riskLevel, RiskLevel.high);
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
