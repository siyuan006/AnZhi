import 'dart:convert';

import 'package:anzhi/services/api_client.dart';
import 'package:anzhi/services/chat_api.dart';
import 'package:anzhi/services/knowledge_api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 安知 —— 测试用假后端
///
/// 用 `package:http` 官方的 [MockClient] 替换真实网络，
/// 因此测的是**真实的 ApiClient / KnowledgeApi 代码路径**，
/// 只有最底层的 socket 被换掉 —— 而不是把被测对象整个 mock 掉。
///
/// 同时记录收到的请求 URI，用来断言「筛选参数确实发给了服务端」，
/// 这是阶段 7 最容易悄悄退化的地方（退回本地过滤）。
class FakeBackend {
  FakeBackend({List<Map<String, dynamic>>? items})
      : items = items ?? defaultItems;

  /// 后端「已发布」的知识条目
  List<Map<String, dynamic>> items;

  /// 依次收到的请求地址，供断言使用
  final List<Uri> requests = <Uri>[];

  /// 设为 true 时模拟「连不上服务器」
  bool offline = false;

  /// 非 2xx 响应
  int? errorStatus;
  Map<String, dynamic> errorBody = <String, dynamic>{'detail': '出错了'};

  /// 非 JSON 响应体（模拟打到了别的服务）
  String? rawBody;

  /// 响应延迟，用于验证超时分支
  Duration? delay;

  // --- AI 问答（POST /api/chat）-------------------------------------------

  /// 依次收到的问答请求体，用来断言「category 没有被当成 null 发出去」
  final List<Map<String, dynamic>> chatRequests = <Map<String, dynamic>>[];

  /// 设为一个非空状态码时，问答返回失败
  int? chatErrorStatus;
  String chatErrorMessage = 'AI 服务未配置，请联系管理员在后端设置 DEEPSEEK_API_KEY';

  /// 问答成功时的响应体，字段与 `docs/API.md` 第 3 节一致
  Map<String, dynamic> chatAnswer = <String, dynamic>{
    'question': '宿舍发生火灾怎么办？',
    'category': '消防安全',
    'risk_level': 'high',
    'answer': '先确保自身安全，再判断是否能够撤离。',
    'steps': <String>['立即报警', '低姿撤离', '不要乘坐电梯'],
    'sources': <String>[],
    'warning': '如已有人受伤，请立即拨打 120。',
  };

  /// 两条已发布的示例知识
  static final List<Map<String, dynamic>> defaultItems = <Map<String, dynamic>>[
    <String, dynamic>{
      'id': 1,
      'title': '宿舍发生火灾如何正确逃生',
      'category_id': 1,
      'category_name': '消防安全',
      'summary': '低姿撤离、不乘电梯、不贪恋财物。',
      'risk_level': 'high',
      'image_url': null,
      'created_at': '2026-09-30T10:00:00',
    },
    <String, dynamic>{
      'id': 2,
      'title': '识别电信诈骗的五个通用信号',
      'category_id': 5,
      'category_name': '网络与反诈安全',
      'summary': '要求转账、索要验证码、制造紧迫感。',
      'risk_level': 'medium',
      'image_url': null,
      'created_at': '2026-09-29T10:00:00',
    },
  ];

  /// 底层 http 客户端（同一个实例被复用，便于断言请求记录）
  late final http.Client httpClient = MockClient(_handle);

  /// 供页面 / 服务测试注入的接口对象
  KnowledgeApi api({Duration? timeout}) => KnowledgeApi(
        client: ApiClient(
          httpClient: httpClient,
          baseUrl: 'http://test.local',
          timeout: timeout,
        ),
      );

  /// 供页面 / 服务测试注入的问答接口对象
  ChatApi chatApi({Duration? timeout}) => ChatApi(
        client: ApiClient(
          httpClient: httpClient,
          baseUrl: 'http://test.local',
          timeout: timeout,
        ),
      );

  /// 直接构造 ApiClient（用于只测客户端本身的用例）
  ApiClient client({Duration? timeout}) => ApiClient(
        httpClient: httpClient,
        baseUrl: 'http://test.local',
        timeout: timeout,
      );

  Future<http.Response> _handle(http.Request request) async {
    requests.add(request.url);

    // 必须在延迟之前记录请求体：否则「请求已发出但还没返回」这段时间里，
    // 记录是空的，用例会把在途请求误判成「压根没发出去」。
    final bool isChat = request.url.path == '/api/chat';
    if (isChat) {
      chatRequests.add(
        jsonDecode(utf8.decode(request.bodyBytes)) as Map<String, dynamic>,
      );
    }

    if (delay != null) await Future<void>.delayed(delay!);

    if (offline) {
      // IOClient 在连接失败时抛出的正是 ClientException
      throw http.ClientException('Connection refused', request.url);
    }

    // AI 问答走独立分支：它的失败语义与其他接口不同，
    // 且有自己的一套响应体，混在一起会让用例难以读懂
    if (isChat) {
      if (chatErrorStatus != null) {
        return _json(<String, dynamic>{'detail': chatErrorMessage}, chatErrorStatus!);
      }
      return _json(chatAnswer, 200);
    }

    if (rawBody != null) {
      return http.Response(rawBody!, errorStatus ?? 200);
    }

    if (errorStatus != null) {
      return _json(errorBody, errorStatus!);
    }

    final String path = request.url.path;
    if (path == '/api/knowledge') {
      return _json(_filtered(request.url.queryParameters), 200);
    }

    if (path.startsWith('/api/knowledge/')) {
      final String rawId = path.substring('/api/knowledge/'.length);
      final int? id = int.tryParse(rawId);
      for (final Map<String, dynamic> item in items) {
        if (item['id'] == id) {
          return _json(<String, dynamic>{
            ...item,
            'content': '正文内容，长度足够用于测试。',
            'source': null,
            'author': null,
            'view_count': 0,
          }, 200);
        }
      }
      return _json(<String, dynamic>{'detail': '知识不存在或未发布'}, 404);
    }

    return _json(<String, dynamic>{'detail': '接口不存在'}, 404);
  }

  /// 模拟服务端筛选，返回统一分页结构
  Map<String, dynamic> _filtered(Map<String, String> query) {
    Iterable<Map<String, dynamic>> result = items;

    final String? categoryId = query['category_id'];
    if (categoryId != null) {
      result = result.where((item) => '${item['category_id']}' == categoryId);
    }

    final String? riskLevel = query['risk_level'];
    if (riskLevel != null) {
      result = result.where((item) => item['risk_level'] == riskLevel);
    }

    final String? keyword = query['keyword'];
    if (keyword != null) {
      result = result.where((item) =>
          '${item['title']}'.contains(keyword) ||
          '${item['summary']}'.contains(keyword));
    }

    final List<Map<String, dynamic>> list = result.toList();
    return <String, dynamic>{
      'total': list.length,
      'page': int.tryParse(query['page'] ?? '1') ?? 1,
      'page_size': int.tryParse(query['page_size'] ?? '20') ?? 20,
      'items': list,
    };
  }

  /// 用 UTF-8 字节构造响应，避免中文在测试中被错误编码
  http.Response _json(Object body, int status) {
    return http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: <String, String>{'content-type': 'application/json'},
    );
  }
}
