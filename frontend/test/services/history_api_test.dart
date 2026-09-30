import 'package:anzhi/models/history_item.dart';
import 'package:anzhi/models/paged_result.dart';
import 'package:anzhi/services/api_client.dart';
import 'package:anzhi/services/history_api.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_backend.dart';

/// 安知 —— 浏览历史接口测试（阶段 11c）
///
/// 这一层要守住的是**与后端约定的那几个语义**：
///   - 未登录返回 401 且说明可读
///   - 两个删除接口都是幂等的
///   - 列表里的嵌套知识能被解析出来（字段名漂移在这里就会暴露）
///   - `viewed_at` 是 naive UTC，能被正确解析成本地时间
void main() {
  group('未登录', () {
    test('三个接口都拿到 401 与「请先登录」', () async {
      final FakeBackend backend = FakeBackend();

      // 不给 token 回调 —— 与生产路径里未登录时完全一致
      final HistoryApi api = backend.historyApi();

      await expectLater(
        api.fetchHistory(),
        throwsA(
          isA<ApiException>()
              .having((ApiException e) => e.statusCode, 'statusCode', 401)
              .having((ApiException e) => e.message, 'message', '请先登录'),
        ),
      );
      await expectLater(
        api.remove(1),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401)),
      );
      await expectLater(
        api.clear(),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401)),
      );
    });
  });

  group('已登录', () {
    late FakeBackend backend;
    late HistoryApi api;
    String? token;

    setUp(() {
      backend = FakeBackend()..seedAccount('xiaoming', 'hunter2hunter2');
      token = 'fake-token-for-xiaoming';
      api = backend.historyApi(token: () => token);
    });

    test('没有任何记录时是空列表而不是报错', () async {
      final PagedResult<HistoryItem> page = await api.fetchHistory();

      expect(page.total, 0);
      expect(page.items, isEmpty);
    });

    test('列表能读出嵌套知识，字段完整', () async {
      backend.seedHistory('xiaoming', 1);

      final PagedResult<HistoryItem> page = await api.fetchHistory();

      expect(page.total, 1);
      final HistoryItem item = page.items.single;
      expect(item.knowledgeId, 1);
      expect(item.viewedAt, isNotNull);
      // 这几条正是「字段名漂移」会在客户端暴露的地方
      expect(item.knowledge.title, '宿舍发生火灾如何正确逃生');
      expect(item.knowledge.categoryId, 1);
      expect(item.isBroken, isFalse);
    });

    test('viewed_at 是 naive UTC，解析后不会偏几个小时', () async {
      // 后端吐的是不带时区的 `2026-09-30T12:00:00` 这种形式。
      // Dart 的 DateTime.parse 会把它当**本地时间**，
      // 那样 UTC+8 的用户看到的会是 8 小时前而不是刚刚。
      backend.seedHistory('xiaoming', 1);

      final HistoryItem item = (await api.fetchHistory()).items.single;

      expect(item.viewedAt, isNotNull);
      expect(item.viewedAt!.isUtc, isFalse, reason: '对外应是本地时间');
      // 刚写进去的记录，解析出来必须贴近当下
      expect(
        DateTime.now().difference(item.viewedAt!).inMinutes.abs(),
        lessThan(2),
        reason: '时区换算错了的话这里会差好几个小时',
      );
    });

    test('最近的排在最前面', () async {
      backend
        ..seedHistory('xiaoming', 1, age: const Duration(hours: 3))
        ..seedHistory('xiaoming', 2, age: const Duration(minutes: 5));

      final PagedResult<HistoryItem> page = await api.fetchHistory();

      expect(
        page.items.map((HistoryItem i) => i.knowledgeId).toList(),
        <int>[2, 1],
      );
    });

    test('删掉一条之后列表里就没有它了', () async {
      backend
        ..seedHistory('xiaoming', 1)
        ..seedHistory('xiaoming', 2);

      await api.remove(1);

      final PagedResult<HistoryItem> page = await api.fetchHistory();
      expect(page.total, 1);
      expect(page.items.single.knowledgeId, 2);
    });

    test('删一条本来就没有的也算成功', () async {
      // 幂等：用户要的是「这条不在我的历史里」，这个状态已经成立了
      await api.remove(999);
    });

    test('清空之后列表变空', () async {
      backend
        ..seedHistory('xiaoming', 1)
        ..seedHistory('xiaoming', 2);

      await api.clear();

      expect((await api.fetchHistory()).total, 0);
    });

    test('清空一个本来就空的历史也算成功', () async {
      await api.clear();
    });

    test('看不到别人的历史', () async {
      // 历史是私密的：看过什么、什么时候看的，都不该被别人读到
      backend
        ..seedAccount('mallory', 'hunter2hunter2')
        ..seedHistory('mallory', 1);

      expect((await api.fetchHistory()).total, 0);
    });

    test('分页参数发出去了，hasMore 与 total 对得上', () async {
      // 假后端的知识目录默认只有 1、2 两条，
      // 用不存在的 id 会连同历史一起被过滤掉（与后端的 INNER JOIN 一致）
      for (int id = 1; id <= 2; id++) {
        backend.seedHistory('xiaoming', id);
      }

      final PagedResult<HistoryItem> first =
          await api.fetchHistory(page: 1, pageSize: 1);

      expect(first.total, 2);
      expect(first.items.length, 1);
      expect(first.hasMore, isTrue);

      final PagedResult<HistoryItem> second =
          await api.fetchHistory(page: 2, pageSize: 1);
      expect(second.items.length, 1);
      expect(second.hasMore, isFalse);
    });

    test('换了 token 就是另一个人了', () async {
      backend
        ..seedAccount('someone-else', 'hunter2hunter2')
        ..seedHistory('xiaoming', 1);

      token = 'fake-token-for-someone-else';

      expect((await api.fetchHistory()).total, 0);
    });
  });

  group('响应体缺字段时', () {
    /// 直接给一个原始响应体。
    ///
    /// 注意**不能带中文**：`http.Response` 拿字符串构造时按 latin1 编码，
    /// 中文会直接抛 "Contains invalid characters"。真实后端返回的是
    /// UTF-8 字节流，不走这条路径。
    HistoryApi rawApi(FakeBackend backend, String body) {
      backend.rawBody = body;
      return backend.historyApi();
    }

    test('嵌套知识为空时标记为已下架，而不是让整页崩掉', () async {
      final HistoryApi api = rawApi(
        FakeBackend(),
        '{"total":1,"page":1,"page_size":20,"items":[{"id":1,'
        '"knowledge_id":1,"viewed_at":"2026-09-30T12:00:00",'
        '"knowledge":{}}]}',
      );

      final HistoryItem item = (await api.fetchHistory()).items.single;

      expect(item.isBroken, isTrue, reason: '标题为空要能被界面识别出来');
      expect(item.knowledgeId, 1, reason: 'knowledge_id 仍在，才能显示成可删除的一行');
    });

    test('viewed_at 解析不了时是 null，而不是抛异常', () async {
      final HistoryApi api = rawApi(
        FakeBackend(),
        '{"total":1,"page":1,"page_size":20,"items":[{"id":1,'
        '"knowledge_id":1,"viewed_at":"not-a-time",'
        '"knowledge":{"id":1,"title":"ok","category_id":1,'
        '"risk_level":"low","summary":"s"}}]}',
      );

      final HistoryItem item = (await api.fetchHistory()).items.single;

      expect(item.viewedAt, isNull);
      expect(item.knowledge.title, 'ok');
    });
  });
}
