import 'package:anzhi/core/app_constants.dart';
import 'package:anzhi/models/knowledge_item.dart';
import 'package:anzhi/models/paged_result.dart';
import 'package:anzhi/services/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_backend.dart';

/// 安知 —— 知识接口测试（阶段 7）
void main() {
  group('列表', () {
    test('解析分页结构与条目字段', () async {
      final PagedResult<KnowledgeItem> result =
          await FakeBackend().api().fetchKnowledge();

      expect(result.total, 2);
      expect(result.page, 1);
      expect(result.items.length, 2);
      expect(result.items.first.title, '宿舍发生火灾如何正确逃生');
      expect(result.items.first.riskLevel, RiskLevel.high);
      // category_name 由后端给出，但客户端以本地分类表为准渲染
      expect(result.items.first.categoryName, '消防安全');
    });

    test('created_at 是 naive UTC，解析后不会偏几个小时', () async {
      // 后端全项目统一存 naive UTC，序列化出来不带 Z。
      // DateTime.parse 遇到这种字符串会当成本地时间，UTC+8 下偏 8 小时。
      // 收藏、浏览历史、帖子都已改用 parseServerTime，这里是最后一处 ——
      // 改回 DateTime.tryParse 这条会红。
      final PagedResult<KnowledgeItem> result =
          await FakeBackend().api().fetchKnowledge();
      final KnowledgeItem item = result.items.first;

      expect(item.createdAt, isNotNull);
      expect(item.createdAt!.isUtc, isFalse, reason: '对外应是本地时间');
      // 假后端这条是 2026-09-30T10:00:00（UTC），换回 UTC 必须还是 10 点
      expect(item.createdAt!.toUtc().hour, 10);
    });

    test('筛选条件发给服务端而不是本地过滤', () async {
      final FakeBackend backend = FakeBackend();

      await backend.api().fetchKnowledge(categoryId: 5, keyword: '诈骗');

      final Uri sent = backend.requests.single;
      expect(sent.queryParameters['category_id'], '5');
      expect(sent.queryParameters['keyword'], '诈骗');

      // 服务端确实按参数筛掉了消防那条
      final PagedResult<KnowledgeItem> result =
          await backend.api().fetchKnowledge(categoryId: 5);
      expect(result.total, 1);
      expect(result.items.single.categoryId, 5);
    });

    test('未筛选时不发送 category_id', () async {
      final FakeBackend backend = FakeBackend();

      await backend.api().fetchKnowledge();

      expect(
        backend.requests.single.queryParameters.containsKey('category_id'),
        isFalse,
      );
    });

    test('关注分类作为重复参数发出去', () async {
      final FakeBackend backend = FakeBackend();

      await backend.api().fetchKnowledge(preferCategoryIds: <int>[1, 5]);

      expect(
        backend.requests.single.queryParametersAll['prefer_categories'],
        <String>['1', '5'],
      );
    });

    test('不传关注分类时不带这个参数', () async {
      final FakeBackend backend = FakeBackend();

      await backend.api().fetchKnowledge();

      expect(
        backend.requests.single.queryParametersAll.containsKey(
          'prefer_categories',
        ),
        isFalse,
      );
    });

    test('关注分类只改变顺序，不会把别的领域筛掉', () async {
      // 假后端照搬后端的两组排序规则，因此这条能真正验证行为而不只是参数
      final FakeBackend backend = FakeBackend();

      final PagedResult<KnowledgeItem> before =
          await backend.api().fetchKnowledge();
      final PagedResult<KnowledgeItem> after =
          await backend.api().fetchKnowledge(preferCategoryIds: <int>[5]);

      expect(after.total, before.total, reason: '关注不等于筛选');
      expect(after.items.first.categoryId, 5, reason: '关注的那个排到最前');
      expect(
        after.items.map((KnowledgeItem i) => i.id).toSet(),
        before.items.map((KnowledgeItem i) => i.id).toSet(),
        reason: '内容一条没少，只是顺序变了',
      );
    });

    test('列表项不含正文（列表接口不返回 content）', () async {
      final PagedResult<KnowledgeItem> result =
          await FakeBackend().api().fetchKnowledge();

      // 一页 20 条若都带正文，流量会被白白浪费
      expect(result.items.every((KnowledgeItem i) => i.content.isEmpty), isTrue);
    });
  });

  group('详情', () {
    test('取到正文与来源字段', () async {
      final KnowledgeItem item = await FakeBackend().api().fetchKnowledgeDetail(1);

      expect(item.id, 1);
      expect(item.content, isNotEmpty);
      expect(item.summary, isNotEmpty);
    });

    test('未发布或不存在的内容返回可读错误', () async {
      await expectLater(
        FakeBackend().api().fetchKnowledgeDetail(999),
        throwsA(
          isA<ApiException>()
              .having((ApiException e) => e.statusCode, 'statusCode', 404)
              .having((ApiException e) => e.message, 'message', '知识不存在或未发布'),
        ),
      );
    });
  });

  group('内容审核状态', () {
    test('后端无已发布内容时如实返回空列表而不是报错', () async {
      // 这正是当前数据库的真实状态：12 条初稿全部待审核
      final FakeBackend backend = FakeBackend(items: <Map<String, dynamic>>[]);

      final PagedResult<KnowledgeItem> result = await backend.api().fetchKnowledge();

      expect(result.total, 0);
      expect(result.items, isEmpty);
      expect(result.hasMore, isFalse);
    });
  });

  group('容错', () {
    test('后端字段缺失时不崩溃，降级为默认值', () async {
      final FakeBackend backend = FakeBackend(
        items: <Map<String, dynamic>>[
          <String, dynamic>{'id': 7},
        ],
      );

      final PagedResult<KnowledgeItem> result = await backend.api().fetchKnowledge();

      final KnowledgeItem item = result.items.single;
      expect(item.id, 7);
      expect(item.title, '');
      expect(item.riskLevel, RiskLevel.low);
      expect(item.categoryName, '未分类');
    });

    test('未知风险等级降级为低风险而不是抛异常', () async {
      final FakeBackend backend = FakeBackend(
        items: <Map<String, dynamic>>[
          <String, dynamic>{'id': 1, 'title': 'x', 'risk_level': 'critical'},
        ],
      );

      final PagedResult<KnowledgeItem> result = await backend.api().fetchKnowledge();
      expect(result.items.single.riskLevel, RiskLevel.low);
    });
  });
}
