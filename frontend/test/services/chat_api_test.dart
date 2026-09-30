import 'package:anzhi/core/app_constants.dart';
import 'package:anzhi/models/ai_answer.dart';
import 'package:anzhi/services/api_client.dart';
import 'package:anzhi/services/chat_api.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_backend.dart';

/// 安知 —— AI 问答接口测试（阶段 8）
///
/// 对应 `docs/API.md` 第 3 节。这里验证的是「请求怎么发出去、
/// 回答怎么被解析」；DeepSeek 本身是否可用无法在此验证（需要真实 Key）。
void main() {
  group('请求', () {
    test('把问题以 JSON 发到 POST /api/chat', () async {
      final FakeBackend backend = FakeBackend();

      await backend.chatApi().ask('宿舍发生火灾怎么办？');

      expect(backend.requests.single.path, '/api/chat');
      expect(backend.chatRequests.single['message'], '宿舍发生火灾怎么办？');
    });

    test('未指定分类时不发送 category，而不是发送 null', () async {
      final FakeBackend backend = FakeBackend();

      await backend.chatApi().ask('插座冒烟了怎么办？');

      // category 的类型是 Optional[str]，发 null 会被当成字符串 "null"
      // 从而让后端把分类识别成「null」这个不存在的名字
      expect(backend.chatRequests.single.containsKey('category'), isFalse);
    });

    test('指定分类时按分类名发送', () async {
      final FakeBackend backend = FakeBackend();

      await backend.chatApi().ask('怎么识别诈骗？', category: '网络与反诈安全');

      expect(backend.chatRequests.single['category'], '网络与反诈安全');
    });

    test('AI 超时是 60 秒，明显长于其他接口的默认超时', () {
      expect(ApiConfig.aiTimeout, const Duration(seconds: 60));
      expect(ApiConfig.aiTimeout, greaterThan(ApiConfig.timeout));
    });

    test('问答请求覆盖客户端默认超时，不会被默认值误杀', () async {
      // 大模型生成一段回答要十几秒，若沿用默认超时，
      // 绝大多数正常提问都会被判为超时。这里把客户端默认超时压到 1ms，
      // 只要 ask() 没有显式覆盖，就必然超时失败。
      final FakeBackend backend = FakeBackend()
        ..delay = const Duration(milliseconds: 50);

      final AiAnswer answer = await ChatApi(
        client: backend.client(timeout: const Duration(milliseconds: 1)),
      ).ask('地震时在室内应该躲哪里？');

      expect(answer.answer, isNotEmpty);
    });
  });

  group('回答解析', () {
    test('解析出正文、风险等级、步骤与警告', () async {
      final AiAnswer answer =
          await FakeBackend().chatApi().ask('宿舍发生火灾怎么办？');

      expect(answer.answer, '先确保自身安全，再判断是否能够撤离。');
      expect(answer.category, '消防安全');
      expect(answer.riskLevel, RiskLevel.high);
      expect(answer.isHighRisk, isTrue);
      expect(answer.steps, hasLength(3));
      expect(answer.steps.first, '立即报警');
      expect(answer.warning, isNotNull);
    });

    test('高风险回答必须带警告，否则页面无从提示用户', () async {
      final AiAnswer answer =
          await FakeBackend().chatApi().ask('宿舍发生火灾怎么办？');

      // PROJECT_SPEC 第十节：高风险问题需要显著的安全提示。
      // 这条断言依赖假后端里那份与后端 ChatService 一致的样例数据。
      expect(answer.riskLevel, RiskLevel.high);
      expect(answer.warning, isNotEmpty);
    });

    test('字段缺失时不崩溃', () async {
      final FakeBackend backend = FakeBackend()
        ..chatAnswer = <String, dynamic>{'answer': '只有正文'};

      final AiAnswer answer = await backend.chatApi().ask('测试');

      expect(answer.answer, '只有正文');
      expect(answer.steps, isEmpty);
      expect(answer.sources, isEmpty);
      expect(answer.riskLevel, RiskLevel.low);
      expect(answer.warning, isNull);
    });

    test('steps 里混入非字符串元素时被过滤掉', () async {
      final FakeBackend backend = FakeBackend()
        ..chatAnswer = <String, dynamic>{
          'answer': '正文',
          'steps': <dynamic>['第一步', 42, null, '第二步'],
        };

      final AiAnswer answer = await backend.chatApi().ask('测试');

      expect(answer.steps, <String>['第一步', '第二步']);
    });
  });

  group('失败', () {
    test('后端未配置 Key 时返回可读中文，不伪造回答', () async {
      final FakeBackend backend = FakeBackend()
        ..chatErrorStatus = 503
        ..chatErrorMessage = 'AI 服务未配置，请联系管理员在后端 .env 中设置 DEEPSEEK_API_KEY';

      await expectLater(
        backend.chatApi().ask('宿舍发生火灾怎么办？'),
        throwsA(
          isA<ApiException>()
              .having((ApiException e) => e.statusCode, 'statusCode', 503)
              .having(
                (ApiException e) => e.message,
                'message',
                contains('DEEPSEEK_API_KEY'),
              ),
        ),
      );
    });

    test('连不上后端时报网络错误而不是超时', () async {
      final FakeBackend backend = FakeBackend()..offline = true;

      await expectLater(
        backend.chatApi().ask('宿舍发生火灾怎么办？'),
        throwsA(
          isA<ApiException>()
              .having((ApiException e) => e.isNetworkError, 'isNetworkError', isTrue),
        ),
      );
    });
  });
}
