import 'package:anzhi/models/paged_result.dart';
import 'package:flutter_test/flutter_test.dart';

/// 安知 —— 分页模型测试
void main() {
  group('解析', () {
    test('标准分页响应：头部字段与逐条转换都正确', () {
      final PagedResult<String> page = PagedResult<String>.fromJson(
        <String, dynamic>{
          'total': 30,
          'page': 2,
          'page_size': 20,
          'items': <dynamic>[
            <String, dynamic>{'title': '甲'},
            <String, dynamic>{'title': '乙'},
          ],
        },
        (Map<String, dynamic> json) => json['title'] as String,
      );

      expect(page.total, 30);
      expect(page.page, 2);
      expect(page.pageSize, 20);
      expect(page.items, <String>['甲', '乙']);
    });

    test('items 里混入非对象元素时跳过而不是崩溃', () {
      final PagedResult<String> page = PagedResult<String>.fromJson(
        <String, dynamic>{
          'total': 3,
          'items': <dynamic>[
            <String, dynamic>{'title': '甲'},
            'not-an-object',
            null,
          ],
        },
        (Map<String, dynamic> json) => json['title'] as String,
      );

      expect(page.items, <String>['甲']);
    });

    test('items 为空数组时不报错', () {
      final PagedResult<String> page = PagedResult<String>.fromJson(
        <String, dynamic>{
          'total': 0,
          'page': 1,
          'page_size': 20,
          'items': <dynamic>[],
        },
        (Map<String, dynamic> json) => json['title'] as String,
      );

      expect(page.items, isEmpty);
      expect(page.total, 0);
    });

    test('items 缺失时降级为空列表', () {
      final PagedResult<String> page = PagedResult<String>.fromJson(
        <String, dynamic>{'total': 0},
        (Map<String, dynamic> json) => '',
      );

      expect(page.items, isEmpty);
      expect(page.page, 1);
      expect(page.pageSize, 20);
    });
  });

  group('hasMore', () {
    test('总数未取完时为 true', () {
      const PagedResult<int> page = PagedResult<int>(
        total: 30,
        page: 1,
        pageSize: 20,
        items: <int>[],
      );
      expect(page.hasMore, isTrue);
    });

    test('最后一页为 false', () {
      const PagedResult<int> page = PagedResult<int>(
        total: 30,
        page: 2,
        pageSize: 20,
        items: <int>[],
      );
      expect(page.hasMore, isFalse);
    });

    test('总数恰好整除页大小时不会多请求一页空数据', () {
      const PagedResult<int> page = PagedResult<int>(
        total: 40,
        page: 2,
        pageSize: 20,
        items: <int>[],
      );
      // 若按「当前页是否满页」判断，这里会错误地认为还有下一页
      expect(page.hasMore, isFalse);
    });
  });

  group('empty', () {
    test('构造空结果', () {
      final PagedResult<int> page = PagedResult.empty<int>(page: 3);
      expect(page.total, 0);
      expect(page.items, isEmpty);
      expect(page.page, 3);
    });
  });
}
