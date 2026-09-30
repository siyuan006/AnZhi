import 'package:anzhi/models/favorite_item.dart';
import 'package:anzhi/models/knowledge_item.dart';
import 'package:anzhi/models/paged_result.dart';
import 'package:anzhi/services/api_client.dart';
import 'package:anzhi/services/favorite_api.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_backend.dart';

/// 安知 —— 收藏接口测试（阶段 11b）
///
/// 这一层要守住的是**与后端约定的那几个语义**：
///   - 未登录返回 401 且说明可读
///   - 收藏 / 取消是幂等的
///   - 列表里的嵌套知识能被解析出来（字段名漂移在这里就会暴露）
void main() {
  group('未登录', () {
    test('三个接口都拿到 401 与「请先登录」', () async {
      final FakeBackend backend = FakeBackend();

      // 不给 token 回调 —— 与生产路径里未登录时完全一致
      final FavoriteApi api = backend.favoriteApi();

      await expectLater(
        api.fetchFavorites(),
        throwsA(
          isA<ApiException>()
              .having((ApiException e) => e.statusCode, 'statusCode', 401)
              .having((ApiException e) => e.message, 'message', '请先登录'),
        ),
      );
      await expectLater(
        api.add(1),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401)),
      );
      await expectLater(
        api.remove(1),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401)),
      );
    });
  });

  group('已登录', () {
    late FakeBackend backend;
    late FavoriteApi api;
    String? token;

    setUp(() {
      backend = FakeBackend()..seedAccount('xiaoming', 'hunter2hunter2');
      token = 'fake-token-for-xiaoming';
      api = backend.favoriteApi(token: () => token);
    });

    test('收藏后列表里能读出来，且嵌套知识字段完整', () async {
      await api.add(1);

      final PagedResult<FavoriteItem> page = await api.fetchFavorites();

      expect(page.total, 1);
      final FavoriteItem item = page.items.single;
      expect(item.knowledgeId, 1);
      expect(item.createdAt, isNotNull);
      // 这几条正是「字段名漂移」会在客户端暴露的地方
      expect(item.knowledge.title, isNotEmpty);
      expect(item.knowledge.title, '宿舍发生火灾如何正确逃生');
      expect(item.knowledge.categoryId, 1);
      expect(item.isBroken, isFalse);
    });

    test('列表按收藏时间倒序，新收藏的在前', () async {
      await api.add(1);
      await api.add(2);

      final PagedResult<FavoriteItem> page = await api.fetchFavorites();

      expect(
        page.items.map((FavoriteItem i) => i.knowledgeId).toList(),
        <int>[2, 1],
      );
    });

    test('重复收藏不报错，总数仍然是 1', () async {
      await api.add(1);
      await api.add(1);

      expect((await api.fetchFavorites()).total, 1);
    });

    test('取消收藏后列表里就没有了', () async {
      await api.add(1);

      await api.remove(1);

      expect((await api.fetchFavorites()).total, 0);
    });

    test('取消一条没收藏过的同样成功', () async {
      await api.remove(1);

      expect((await api.fetchFavorites()).total, 0);
    });

    test('收藏不存在的知识返回 404 与可读原因', () async {
      await expectLater(
        api.add(999999),
        throwsA(
          isA<ApiException>()
              .having((ApiException e) => e.statusCode, 'statusCode', 404)
              .having((ApiException e) => e.message, 'message', '知识不存在或未发布'),
        ),
      );
    });

    test('token 变了之后用的是新的身份', () async {
      // token 是**回调**而不是字段，就是为了让换账号立刻生效
      await api.add(1);
      backend.seedAccount('mallory', 'hunter2hunter2');
      token = 'fake-token-for-mallory';

      expect((await api.fetchFavorites()).total, 0, reason: '换账号不该看到上一个账号的收藏');
    });

    test('分页：page_size 生效，total 是符合条件的总数', () async {
      await api.add(1);
      await api.add(2);

      final PagedResult<FavoriteItem> first =
          await api.fetchFavorites(page: 1, pageSize: 1);
      final PagedResult<FavoriteItem> second =
          await api.fetchFavorites(page: 2, pageSize: 1);

      expect(first.total, 2);
      expect(first.items, hasLength(1));
      expect(first.hasMore, isTrue);
      expect(second.items, hasLength(1));
      expect(second.hasMore, isFalse);
      expect(second.items.single.knowledgeId, isNot(first.items.single.knowledgeId));
    });
  });

  group('响应体缺字段时', () {
    test('缺了嵌套知识的那一条降级为「内容已下架」，而不是抛异常', () {
      // 一条解析不了的数据不该让整个收藏页打不开。
      // 真实后端不会这么返回（列表用 INNER JOIN 过滤过），
      // 但客户端不该把「数据异常」变成「页面白屏」。
      final FavoriteItem broken = FavoriteItem.fromJson(<String, dynamic>{
        'id': 7,
        'knowledge_id': 42,
        'created_at': '2026-09-30T12:00:00',
      });

      expect(broken.id, 7);
      expect(broken.knowledgeId, 42);
      expect(broken.knowledge.title, isEmpty);
      expect(broken.isBroken, isTrue);
    });

    test('缺少 is_favorited 时按未收藏处理', () {
      // 老版本后端、或者字段还没上线时，不能因为读不到就崩
      final KnowledgeItem item = KnowledgeItem.fromJson(
        <String, dynamic>{'id': 1, 'title': '标题'},
      );

      expect(item.isFavorited, isFalse);
    });
  });
}
