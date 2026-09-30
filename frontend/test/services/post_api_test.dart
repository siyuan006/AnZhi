import 'package:anzhi/models/paged_result.dart';
import 'package:anzhi/models/post_item.dart';
import 'package:anzhi/services/api_client.dart';
import 'package:anzhi/services/post_api.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_backend.dart';

/// 安知 —— 社区接口测试（阶段 12a）
///
/// 这一层要守住的是与后端约定的几件事：
///   - 列表项**没有正文**，只有摘要（拿它当详情用会渲染出空白）
///   - 嵌套的作者能被解析出来，且**没有 username**
///   - 没有分类的帖子是合法的（`category_id` 可空）
///   - 帖子不存在 / 已隐藏时是可读的 404
void main() {
  late FakeBackend backend;
  late PostApi api;

  setUp(() {
    backend = FakeBackend();
    api = backend.postApi();
  });

  test('列表能读出后端返回的条目', () async {
    final PagedResult<PostItem> page = await api.fetchPosts();

    expect(page.total, 2);
    expect(page.items.first.title, '宿舍用电的几点提醒');
  });

  test('列表项不带正文，只有摘要', () async {
    // 这条是「列表」与「详情」的边界：把 summary 当 content 用，
    // 详情页会渲染出一片空白，而且不会有任何报错
    final PostItem item = (await api.fetchPosts()).items.first;

    expect(item.summary, isNotEmpty);
    expect(item.content, isEmpty);
    expect(item.hasContent, isFalse);
  });

  test('作者能解析出来，且没有 username 字段', () async {
    final PostItem item = (await api.fetchPosts()).items.first;

    expect(item.author, isNotNull);
    expect(item.authorName, '小艾');
    expect(item.author!.initial, '小');
  });

  test('没有分类的帖子不会崩，只是不显示分类标签', () async {
    // 帖子可以不属于任何分类（数据库里 category_id 可空），
    // 这是真实存在的情况，不是脏数据
    final PagedResult<PostItem> page = await api.fetchPosts();
    final PostItem uncategorised =
        page.items.firstWhere((PostItem p) => p.title.contains('诈骗'));

    expect(uncategorised.categoryId, isNull);
    expect(uncategorised.categoryName, isEmpty);
    expect(uncategorised.category, isNull);
  });

  test('有分类的帖子能把分类名解析成本地分类', () async {
    final PostItem item = (await api.fetchPosts()).items.first;

    expect(item.categoryId, 2);
    expect(item.category, isNotNull);
    expect(item.categoryName, isNot('未分类'));
  });

  test('created_at 是 naive UTC，解析后不会偏几个小时', () async {
    // 与浏览历史同一个坑：后端吐的时间戳不带 Z，
    // 直接 DateTime.parse 会当成本地时间，UTC+8 下偏 8 小时。
    final PostItem item = (await api.fetchPosts()).items.first;

    expect(item.createdAt, isNotNull);
    expect(item.createdAt!.isUtc, isFalse, reason: '对外应是本地时间');
    // 假后端的这条是 2026-09-30T10:00:00Z，换算到 UTC 必须还是 10 点
    expect(item.createdAt!.toUtc().hour, 10);
  });

  test('详情能读到正文全文', () async {
    final PostItem item = await api.fetchPostDetail(1);

    expect(item.hasContent, isTrue);
    expect(item.content, contains('插排'));
    expect(item.title, '宿舍用电的几点提醒');
  });

  test('详情不存在时抛出可读的 404', () async {
    await expectLater(
      api.fetchPostDetail(999999),
      throwsA(
        isA<ApiException>()
            .having((ApiException e) => e.statusCode, 'statusCode', 404)
            .having((ApiException e) => e.message, 'message', '帖子不存在或已删除'),
      ),
    );
  });

  test('按分类筛选只返回该分类的帖子', () async {
    final PagedResult<PostItem> page = await api.fetchPosts(categoryId: 2);

    expect(page.items, isNotEmpty);
    expect(page.items.every((PostItem p) => p.categoryId == 2), isTrue);
  });

  test('搜索能命中标题与正文', () async {
    expect((await api.fetchPosts(keyword: '插排')).total, 1);
    expect((await api.fetchPosts(keyword: '诈骗')).total, 1);
    expect((await api.fetchPosts(keyword: '不存在的关键词xyz')).total, 0);
  });

  test('分页参数发出去了，total 与列表对得上', () async {
    final PagedResult<PostItem> first = await api.fetchPosts(page: 1, pageSize: 1);

    expect(first.total, 2, reason: 'total 是总数，不受分页影响');
    expect(first.items.length, 1);
    expect(first.hasMore, isTrue);

    final PagedResult<PostItem> second = await api.fetchPosts(page: 2, pageSize: 1);
    expect(second.items.length, 1);
    expect(second.hasMore, isFalse);
  });

  test('没有人发帖时是空列表而不是报错', () async {
    backend.seedNoPosts();

    final PagedResult<PostItem> page = await api.fetchPosts();

    expect(page.total, 0);
    expect(page.items, isEmpty);
  });

  group('响应体缺字段时', () {
    /// 注意**不能带中文**：`http.Response` 拿字符串构造时按 latin1 编码，
    /// 中文会直接抛 "Contains invalid characters"。
    PostApi rawApi(String body) {
      backend.rawBody = body;
      return backend.postApi();
    }

    test('作者缺失时不会崩，署名降级为「匿名用户」', () async {
      final PostApi raw = rawApi(
        '{"total":1,"page":1,"page_size":20,"items":[{"id":1,'
        '"title":"ok","summary":"s"}]}',
      );

      final PostItem item = (await raw.fetchPosts()).items.single;

      expect(item.author, isNull);
      expect(item.authorName, '匿名用户');
      expect(item.title, 'ok');
    });

    test('created_at 解析不了时是 null，而不是抛异常', () async {
      final PostApi raw = rawApi(
        '{"total":1,"page":1,"page_size":20,"items":[{"id":1,'
        '"title":"ok","summary":"s","created_at":"not-a-time"}]}',
      );

      final PostItem item = (await raw.fetchPosts()).items.single;

      expect(item.createdAt, isNull);
      expect(item.title, 'ok');
    });
  });
}
