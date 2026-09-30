import '../core/app_constants.dart';

/// 安知 —— AI 回答结构
///
/// 严格对应 PROJECT_SPEC.md 第九节的回答 JSON：
/// ```json
/// {
///   "question": "...",
///   "category": "...",
///   "risk_level": "high",
///   "answer": "...",
///   "steps": ["..."],
///   "sources": ["..."],
///   "warning": "..."
/// }
/// ```
///
/// AI 回答不是纯文本，而是结构化数据：
/// 风险等级决定展示方式，steps 是可直接执行的步骤，
/// warning 在高风险时给出安全警告。
class AiAnswer {
  const AiAnswer({
    required this.question,
    required this.answer,
    this.category,
    this.riskLevel = RiskLevel.low,
    this.steps = const <String>[],
    this.sources = const <String>[],
    this.warning,
  });

  final String question;
  final String answer;

  /// 分类名（后端返回中文字符串，非 id）
  final String? category;
  final RiskLevel riskLevel;

  /// 可执行步骤。高风险问题应非空（PROJECT_SPEC 第十一节）
  final List<String> steps;

  /// 来源引用。V1.0 可为空，V2.0 RAG 填充（第四十三节）
  final List<String> sources;

  /// 安全警告。medium / high 时应非空
  final String? warning;

  /// 是否为高风险回答 —— 高风险需要更醒目的视觉呈现
  bool get isHighRisk => riskLevel == RiskLevel.high;

  factory AiAnswer.fromJson(Map<String, dynamic> json) {
    return AiAnswer(
      question: json['question'] as String? ?? '',
      answer: json['answer'] as String? ?? '',
      category: json['category'] as String?,
      riskLevel: RiskLevel.fromValue(json['risk_level'] as String?),
      steps: _stringList(json['steps']),
      sources: _stringList(json['sources']),
      warning: json['warning'] as String?,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'question': question,
        'answer': answer,
        'category': category,
        'risk_level': riskLevel.value,
        'steps': steps,
        'sources': sources,
        'warning': warning,
      };

  /// 容错解析字符串数组，兼容后端返回 null 或非字符串元素
  static List<String> _stringList(dynamic value) {
    if (value is! List) return const <String>[];
    return value.whereType<String>().toList(growable: false);
  }
}

/// 聊天记录中的一条消息
class ChatMessage {
  ChatMessage.user(this.text)
      : isUser = true,
        answer = null,
        isError = false;

  ChatMessage.assistant(this.answer)
      : isUser = false,
        text = '',
        isError = false;

  /// 本地错误提示（网络异常、后端未连接等），不是 AI 回答
  ChatMessage.error(this.text)
      : isUser = false,
        answer = null,
        isError = true;

  final bool isUser;

  /// 用户消息文本；AI 消息时为空
  final String text;

  /// AI 结构化回答；用户消息与错误消息时为 null
  final AiAnswer? answer;

  /// 是否为错误提示。错误消息必须与 AI 回答区分显示，
  /// 避免把「后端未连接」误认为「AI 已正式回答」
  final bool isError;

  DateTime get timestamp => DateTime.now();
}
