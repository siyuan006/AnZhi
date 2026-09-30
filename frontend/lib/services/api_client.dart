import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// 安知 —— 后端接口客户端
///
/// 职责边界（PROJECT_SPEC 第五十二节：api → services → models 单向依赖）：
///   - 本文件只负责「发请求 / 解析 JSON / 把各种失败翻译成人话」
///   - 页面只负责渲染，不直接碰 HTTP
///   - 业务语义（知识、分类、AI 问答）放在各自的服务类里
///
/// ⚠️ Flutter 端不持有任何第三方密钥（PROJECT_SPEC 第三十五节、四十六节）。
/// DeepSeek 的 API Key 只存在于后端 `.env`，本文件从不涉及。

// ---------------------------------------------------------------------------
// 服务地址
// ---------------------------------------------------------------------------

/// 后端地址配置。
///
/// 不同运行环境访问同一个后端的地址并不相同，这是最容易踩的坑：
///
/// | 运行环境 | 应使用的地址 |
/// |---|---|
/// | Android 模拟器 | `10.0.2.2`（模拟器映射到宿主机的固定地址） |
/// | 真机（同一局域网） | 电脑的局域网 IP，如 `192.168.1.5` |
/// | Windows / macOS 桌面 | `127.0.0.1` |
///
/// 默认值按「Android 模拟器」设置，因为它不需要任何额外配置就能跑通；
/// 真机调试时用 `--dart-define` 覆盖，无需改代码：
///
/// ```bash
/// flutter run --dart-define=ANZHI_API_BASE_URL=http://192.168.1.5:8000
/// ```
class ApiConfig {
  const ApiConfig._();

  /// 由 `--dart-define=ANZHI_API_BASE_URL=...` 注入，未注入时为空串
  static const String _override = String.fromEnvironment(
    'ANZHI_API_BASE_URL',
  );

  /// 请求超时时间。超时过长会让用户以为 App 卡死，
  /// 过短则会在网络较慢时误报失败。
  static const Duration timeout = Duration(seconds: 10);

  /// 后端根地址（不含结尾斜杠）
  static String get baseUrl {
    if (_override.isNotEmpty) return _override;
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8000';
    }
    return 'http://127.0.0.1:8000';
  }
}

// ---------------------------------------------------------------------------
// 统一异常
// ---------------------------------------------------------------------------

/// 接口调用失败。
///
/// 所有网络层异常都会被翻译成这个类型再抛出，
/// 页面因此只需要 `catch (ApiException e)` 一种写法，
/// 并且 [message] 一定是可以直接显示给用户的中文。
///
/// 网络故障是必然会发生的（后端没启动、WiFi 断了、手机没信号），
/// 页面必须能在任何一条失败路径上给出提示而不是崩溃。
class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode, this.isNetworkError = false});

  /// 面向用户的中文提示
  final String message;

  /// HTTP 状态码；网络层失败（压根没连上）时为 `null`
  final int? statusCode;

  /// 是否是「连不上 / 超时」这类网络问题。
  /// 页面据此提示「检查网络或后端是否已启动」，比单纯报错更有帮助。
  final bool isNetworkError;

  @override
  String toString() => 'ApiException(${statusCode ?? 'network'}): $message';
}

// ---------------------------------------------------------------------------
// 客户端
// ---------------------------------------------------------------------------

/// 极简 JSON 客户端。
///
/// 只实现 GET —— 当前阶段（阶段 7）后端对外只有 GET 接口；
/// 等阶段 8 的 `POST /api/chat` 落地时再扩展，避免现在写一堆用不到的代码。
class ApiClient {
  ApiClient({http.Client? httpClient, String? baseUrl, Duration? timeout})
      : _http = httpClient ?? http.Client(),
        _baseUrl = baseUrl ?? ApiConfig.baseUrl,
        _timeout = timeout ?? ApiConfig.timeout;

  final http.Client _http;
  final String _baseUrl;

  /// 可覆盖，便于测试用极短超时验证超时分支
  final Duration _timeout;

  /// 发起 GET 请求并返回解析后的 JSON。
  ///
  /// 返回类型是 `Object?`，因为顶层既可能是对象也可能是数组，
  /// 由各业务服务自行断言成具体类型。
  Future<Object?> getJson(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    final Uri uri = Uri.parse('$_baseUrl$path').replace(
      queryParameters: _cleanQuery(query),
    );

    late final http.Response response;
    try {
      response = await _http.get(uri).timeout(_timeout);
    } on TimeoutException {
      throw const ApiException(
        '请求超时，请检查网络后重试',
        isNetworkError: true,
      );
    } on http.ClientException {
      // 后端没启动、地址写错、WiFi 断开都会走到这里
      throw const ApiException(
        '无法连接到服务器，请确认后端已启动、地址配置正确',
        isNetworkError: true,
      );
    }

    return _decode(response);
  }

  /// 解析响应体。
  ///
  /// 分三步走：状态码 → 解码 JSON → 取出错误说明。
  /// 任何一步失败都抛出带上文的中文异常，绝不把原始异常抛给页面。
  Object? _decode(http.Response response) {
    final String body = utf8.decode(response.bodyBytes, allowMalformed: true);

    Object? decoded;
    if (body.isNotEmpty) {
      try {
        decoded = jsonDecode(body);
      } on FormatException {
        // 返回了 HTML（例如打到了别的服务）或后端崩溃输出了非 JSON 内容
        throw ApiException(
          '服务器返回的数据格式不正确（HTTP ${response.statusCode}）',
          statusCode: response.statusCode,
        );
      }
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded;
    }

    throw ApiException(
      _errorMessage(decoded, response.statusCode),
      statusCode: response.statusCode,
    );
  }

  /// 从统一错误结构 `{"detail": "..."}` 中取出说明。
  ///
  /// 后端全局异常处理器保证错误响应都是这个形状，
  /// 但 422 会多带一个 `errors` 列表，这里优先用第一条更具体的描述。
  String _errorMessage(Object? decoded, int statusCode) {
    if (decoded is Map<String, dynamic>) {
      final Object? errors = decoded['errors'];
      if (errors is List && errors.isNotEmpty) {
        final Object? first = errors.first;
        if (first is Map && first['message'] != null) {
          return first['message'].toString();
        }
      }
      final Object? detail = decoded['detail'];
      if (detail is String && detail.isNotEmpty) return detail;
    }
    return '请求失败（HTTP $statusCode）';
  }

  /// 去掉值为 `null` 的查询参数。
  ///
  /// 不能把 `category_id=null` 发给后端：FastAPI 会按字符串 "null" 解析，
  /// 直接返回 422，表现为「不选分类反而报错」。
  Map<String, String> _cleanQuery(Map<String, dynamic>? query) {
    if (query == null) return <String, String>{};

    final Map<String, String> result = <String, String>{};
    query.forEach((String key, dynamic value) {
      if (value == null) return;
      final String text = value.toString();
      if (text.isEmpty) return;
      result[key] = text;
    });
    return result;
  }

  void close() => _http.close();
}
