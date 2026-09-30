import '../models/ai_answer.dart';
import 'api_client.dart';

/// 安知 —— AI 问答接口
///
/// 对应 `docs/API.md` 第 3 节：`POST /api/chat`。
///
/// 完整的链路是：本文件 → FastAPI → ChatService → DeepSeek。
/// **Flutter 端不持有 DeepSeek 的 API Key**（PROJECT_SPEC 第三十五节），
/// 密钥只存在于后端的 `.env` 里。
class ChatApi {
  ChatApi({ApiClient? client}) : _client = client ?? ApiClient();

  final ApiClient _client;

  /// 提问并返回结构化回答。
  ///
  /// 超时用 [ApiConfig.aiTimeout]（60 秒）而不是默认的 10 秒：
  /// 大模型生成回答通常要十几秒，用默认值会让正常提问被误判为超时。
  ///
  /// 失败时抛 [ApiException]，[ApiException.message] 是可以直接显示的中文，
  /// 页面不需要区分「是没配 Key 还是超时」—— 后端已经翻译过一次了。
  Future<AiAnswer> ask(String message, {String? category}) async {
    final Object? json = await _client.postJson(
      '/api/chat',
      <String, dynamic>{'message': message, 'category': ?category},
      timeout: ApiConfig.aiTimeout,
    );

    if (json is! Map<String, dynamic>) {
      throw const ApiException('AI 服务返回格式不正确');
    }
    return AiAnswer.fromJson(json);
  }

  void dispose() => _client.close();
}
