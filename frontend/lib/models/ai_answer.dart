import '../core/app_constants.dart';
import 'knowledge_item.dart';

/// 安知 —— AI 回答里引用到的知识卡片（阶段 14）
///
/// 与 `AiAnswer.sources` 的区别在于**能不能核实**：
/// `sources` 是模型自己写下的依据，无法验证真假；
/// 本类的每一条都来自后端知识库中已发布的卡片，带有 id，
/// 可以点进去读原文。
class KnowledgeReference {
  const KnowledgeReference({
    required this.id,
    required this.title,
    this.summary = '',
    this.categoryId = 0,
    this.riskLevel = RiskLevel.low,
  });

  final int id;
  final String title;
  final String summary;

  /// 对应 `categories.id`
  final int categoryId;
  final RiskLevel riskLevel;

  /// 所属分类，找不到时返回 `null`
  SafetyCategory? get category => categoryById(categoryId);

  /// 分类显示名，找不到分类时降级为「未分类」
  String get categoryName => category?.name ?? '未分类';

  /// 转成知识详情页的预览数据。
  ///
  /// 详情页有 `preview` 就能先把页头画出来，用户点进去立刻看到
  /// 自己点的那一条，而不是一个整页的转圈。
  KnowledgeItem toPreview() => KnowledgeItem(
        id: id,
        title: title,
        categoryId: categoryId,
        summary: summary,
        riskLevel: riskLevel,
      );

  factory KnowledgeReference.fromJson(Map<String, dynamic> json) {
    return KnowledgeReference(
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: json['title'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      categoryId: (json['category_id'] as num?)?.toInt() ?? 0,
      riskLevel: RiskLevel.fromValue(json['risk_level'] as String?),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'summary': summary,
        'category_id': categoryId,
        'risk_level': riskLevel.value,
      };
}

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
///   "references": [{"id": 1, "title": "..."}],
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
    this.references = const <KnowledgeReference>[],
    this.warning,
  });

  final String question;
  final String answer;

  /// 分类名（后端返回中文字符串，非 id）
  final String? category;
  final RiskLevel riskLevel;

  /// 可执行步骤。高风险问题应非空（PROJECT_SPEC 第十一节）
  final List<String> steps;

  /// 模型给出的公开依据。**无法核实**，界面上要与 [references] 分开呈现
  final List<String> sources;

  /// 后端从知识库检索到的卡片（PROJECT_SPEC 第十四节 V1.5）。
  /// 知识库没有相关内容时为空 —— 空不代表出错
  final List<KnowledgeReference> references;

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
      references: _referenceList(json['references']),
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
        'references': <Map<String, dynamic>>[
          for (final KnowledgeReference item in references) item.toJson(),
        ],
        'warning': warning,
      };

  /// 容错解析字符串数组，兼容后端返回 null 或非字符串元素
  static List<String> _stringList(dynamic value) {
    if (value is! List) return const <String>[];
    return value.whereType<String>().toList(growable: false);
  }

  /// 容错解析引用数组，跳过结构不对的条目而不是整条回答解析失败
  static List<KnowledgeReference> _referenceList(dynamic value) {
    if (value is! List) return const <KnowledgeReference>[];
    return <KnowledgeReference>[
      for (final dynamic item in value)
        if (item is Map<String, dynamic>) KnowledgeReference.fromJson(item),
    ];
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
