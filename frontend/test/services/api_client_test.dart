import 'package:anzhi/services/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_backend.dart';

/// 安知 —— 接口客户端测试（阶段 7）
///
/// 网络故障是必然事件而不是异常情况：后端没启动、WiFi 断了、地址配错。
/// 这一组测试保证**每一种失败都有可读的中文提示**，
/// 而不是把原始异常抛到页面上导致白屏或崩溃。
void main() {
  group('成功路径', () {
    test('解析 UTF-8 中文响应', () async {
      final FakeBackend backend = FakeBackend();

      final Object? json = await backend.client().getJson('/api/knowledge');

      final Map<String, dynamic> body = json! as Map<String, dynamic>;
      expect(body['total'], 2);
      // 中文没有乱码，说明按 UTF-8 解码而不是按 latin1
      final List<dynamic> items = body['items'] as List<dynamic>;
      expect((items.first as Map<String, dynamic>)['title'], '宿舍发生火灾如何正确逃生');
    });
  });

  group('参数处理', () {
    test('null 与空串的查询参数不会发给后端', () async {
      final FakeBackend backend = FakeBackend();

      await backend.client().getJson(
        '/api/knowledge',
        query: <String, dynamic>{
          'category_id': null,
          'keyword': '',
          'page': 1,
        },
      );

      final Uri sent = backend.requests.single;
      // 发 category_id=null 会被 FastAPI 按字符串解析并返回 422，
      // 表现为「不选分类反而报错」，因此必须剔除
      expect(sent.queryParameters.containsKey('category_id'), isFalse);
      expect(sent.queryParameters.containsKey('keyword'), isFalse);
      expect(sent.queryParameters['page'], '1');
    });
  });

  group('错误翻译', () {
    test('连不上服务器时给出中文提示且标记为网络错误', () async {
      final FakeBackend backend = FakeBackend()..offline = true;

      await expectLater(
        backend.client().getJson('/api/knowledge'),
        throwsA(
          isA<ApiException>()
              .having((ApiException e) => e.isNetworkError, 'isNetworkError', isTrue)
              .having((ApiException e) => e.statusCode, 'statusCode', isNull)
              .having((ApiException e) => e.message, 'message', contains('无法连接')),
        ),
      );
    });

    test('超时不会一直挂着，而是抛出可读提示', () async {
      final FakeBackend backend = FakeBackend()
        ..delay = const Duration(seconds: 2);

      await expectLater(
        backend.client(timeout: const Duration(milliseconds: 40)).getJson(
              '/api/knowledge',
            ),
        throwsA(
          isA<ApiException>()
              .having((ApiException e) => e.isNetworkError, 'isNetworkError', isTrue)
              .having((ApiException e) => e.message, 'message', contains('超时')),
        ),
      );
    });

    test('404 使用后端返回的 detail', () async {
      final FakeBackend backend = FakeBackend()
        ..errorStatus = 404
        ..errorBody = <String, dynamic>{'detail': '知识不存在或未发布'};

      await expectLater(
        backend.client().getJson('/api/knowledge/999'),
        throwsA(
          isA<ApiException>()
              .having((ApiException e) => e.statusCode, 'statusCode', 404)
              .having((ApiException e) => e.message, 'message', '知识不存在或未发布'),
        ),
      );
    });

    test('422 优先展示字段级错误说明', () async {
      final FakeBackend backend = FakeBackend()
        ..errorStatus = 422
        ..errorBody = <String, dynamic>{
          'detail': '请求参数校验失败',
          'errors': <dynamic>[
            <String, dynamic>{'field': 'page', 'message': 'page 必须大于等于 1'},
          ],
        };

      await expectLater(
        backend.client().getJson('/api/knowledge'),
        throwsA(
          isA<ApiException>()
              .having((ApiException e) => e.message, 'message', 'page 必须大于等于 1'),
        ),
      );
    });

    test('500 且 detail 为空时仍给出可读提示', () async {
      final FakeBackend backend = FakeBackend()
        ..errorStatus = 500
        ..errorBody = <String, dynamic>{'detail': ''};

      await expectLater(
        backend.client().getJson('/api/knowledge'),
        throwsA(
          isA<ApiException>()
              .having((ApiException e) => e.message, 'message', contains('HTTP 500')),
        ),
      );
    });

    test('响应不是 JSON 时提示格式错误而不是崩溃', () async {
      final FakeBackend backend = FakeBackend()..rawBody = '<html>502</html>';

      await expectLater(
        backend.client().getJson('/api/knowledge'),
        throwsA(
          isA<ApiException>()
              .having((ApiException e) => e.message, 'message', contains('格式不正确')),
        ),
      );
    });
  });

  group('地址配置', () {
    test('默认地址带端口且指向本机可直连的地址', () {
      // 默认值必须开箱即用：模拟器用 10.0.2.2，桌面端用 127.0.0.1
      expect(ApiConfig.baseUrl, contains(':8000'));
      expect(
        ApiConfig.baseUrl,
        anyOf(contains('10.0.2.2'), contains('127.0.0.1')),
      );
    });
  });
}
