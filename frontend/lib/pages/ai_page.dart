import 'package:flutter/material.dart';

import '../core/app_constants.dart';
import '../core/app_theme.dart';
import '../models/ai_answer.dart';
import '../services/api_client.dart';
import '../services/chat_api.dart';
import '../widgets/risk_badge.dart';

/// 安知 —— AI 安全问答页
///
/// 项目核心功能之一（PROJECT_SPEC 第八节）。
///
/// 链路（阶段 8 接通）：
///   用户输入 → POST /api/chat → FastAPI → ChatService → DeepSeek
///   → 结构化回答 → 本页渲染
///
/// ⚠️ 尚未实现：SafetyGuard 内容审查（PROJECT_SPEC 第三十七节，阶段 9）。
/// 当前回答只经过**结构性校验**（字段齐全、风险等级可识别、
/// 中高风险带警告），不等于已通过安全审查。
///
/// 失败时展示后端返回的中文说明（未配置 Key / 超时 / 限流等），
/// **不会伪造任何 AI 回答**。
class AiPage extends StatefulWidget {
  const AiPage({super.key, this.api});

  /// 允许注入，便于测试用假客户端替换真实网络
  final ChatApi? api;

  @override
  State<AiPage> createState() => _AiPageState();
}

class _AiPageState extends State<AiPage> {
  late final ChatApi _api = widget.api ?? ChatApi();
  late final bool _ownsApi = widget.api == null;

  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = <ChatMessage>[];

  /// 是否正在等待 AI 回答。等待期间禁止重复发送，
  /// 否则连续点击会并发发出多个请求。
  bool _sending = false;

  /// 常见问题示例，帮助用户快速上手
  static const List<String> _suggestions = <String>[
    '宿舍发生火灾怎么办？',
    '电动车可以在楼道充电吗？',
    '插座冒烟了该怎么处理？',
    '怎么识别电信诈骗？',
    '地震时在室内应该躲哪里？',
  ];

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    if (_ownsApi) _api.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    // 等待列表完成布局后再滚动，否则拿不到最新 maxScrollExtent
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send([String? preset]) async {
    final String question = (preset ?? _inputController.text).trim();
    if (question.isEmpty || _sending) return;

    setState(() {
      _messages.add(ChatMessage.user(question));
      _sending = true;
    });

    _inputController.clear();
    _scrollToBottom();

    try {
      final AiAnswer answer = await _api.ask(question);
      if (!mounted) return;
      setState(() {
        _messages.add(ChatMessage.assistant(answer));
        _sending = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      // 后端已经把失败原因翻译成中文（未配置 Key / 超时 / 限流……），
      // 这里原样展示，不重新编造一句更含糊的提示
      setState(() {
        _messages.add(ChatMessage.error(error.message));
        _sending = false;
      });
    }

    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackgroundColor,
      appBar: AppBar(
        title: const Text('AI 安全助手'),
        actions: <Widget>[
          IconButton(
            onPressed: _messages.isEmpty || _sending
                ? null
                : () => setState(() => _messages.clear()),
            icon: const Icon(Icons.delete_outline_rounded),
            tooltip: '清空对话',
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: _messages.isEmpty
                ? _EmptyState(
                    suggestions: _suggestions,
                    onSuggestionTap: _send,
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(
                      kPagePadding,
                      12,
                      kPagePadding,
                      16,
                    ),
                    // 等待回答时多渲染一个「思考中」气泡
                    itemCount: _messages.length + (_sending ? 1 : 0),
                    itemBuilder: (BuildContext context, int index) {
                      if (index == _messages.length) return const _ThinkingBubble();
                      return _MessageBubble(message: _messages[index]);
                    },
                  ),
          ),
          _InputBar(
            controller: _inputController,
            onSend: _send,
            enabled: !_sending,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 空状态：引导 + 安全声明
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.suggestions,
    required this.onSuggestionTap,
  });

  final List<String> suggestions;
  final void Function(String question) onSuggestionTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(kPagePadding, 32, kPagePadding, 16),
      children: <Widget>[
        Center(
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              Icons.auto_awesome,
              size: 32,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          '有安全方面的问题，随时问我',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '我会给出可执行的步骤和必要的安全提醒',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 26),

        Text(
          '试试这些问题',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        for (final String q in suggestions)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: kSurfaceColor,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: () => onSuggestionTap(q),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 13,
                  ),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          q,
                          style: const TextStyle(fontSize: 13.5),
                        ),
                      ),
                      Icon(
                        Icons.north_east_rounded,
                        size: 15,
                        color: theme.colorScheme.outline,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

        const SizedBox(height: 20),
        const _SafetyNotice(),
      ],
    );
  }
}

/// 安全声明 —— 高风险场景下用户不应依赖 App 而延误求助
class _SafetyNotice extends StatelessWidget {
  const _SafetyNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF6E5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFE0A3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(
            Icons.info_outline_rounded,
            size: 17,
            color: Color(0xFFB26A00),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              '遇到紧急危险，请立即拨打 119 / 120 / 110，'
              '不要因为等待 App 回答而延误处置。',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.55,
                color: const Color(0xFF8A5300),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 消息气泡
// ---------------------------------------------------------------------------

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    if (message.isUser) return _UserBubble(text: message.text);
    if (message.isError) return _ErrorBubble(text: message.text);
    return _AnswerBubble(answer: message.answer!);
  }
}

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14, left: 48),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(14),
            topRight: Radius.circular(14),
            bottomLeft: Radius.circular(14),
            bottomRight: Radius.circular(4),
          ),
        ),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14.5,
            height: 1.5,
          ),
        ),
      ),
    );
  }
}

/// 本地错误/提示气泡 —— 视觉上与 AI 回答明显区分
class _ErrorBubble extends StatelessWidget {
  const _ErrorBubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14, right: 32),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF6E5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFE0A3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(
            Icons.info_outline_rounded,
            size: 17,
            color: Color(0xFFB26A00),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                height: 1.6,
                color: Color(0xFF8A5300),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// AI 结构化回答气泡
///
/// 高风险回答优先展示 warning 与 steps（PROJECT_SPEC 第十、十一节）：
/// 生命安全优先 → 可执行步骤 → 知识解释 → 来源。
class _AnswerBubble extends StatelessWidget {
  const _AnswerBubble({required this.answer});

  final AiAnswer answer;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 14, right: 32),
      decoration: BoxDecoration(
        color: kSurfaceColor,
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (answer.category != null)
                Text(
                  answer.category!,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.primary,
                  ),
                ),
              const Spacer(),
              RiskBadge(level: answer.riskLevel, compact: true),
            ],
          ),
          const SizedBox(height: 11),

          // 安全警告置于正文之前 —— 高风险时用户应先看到它
          if (answer.warning != null && answer.warning!.isNotEmpty) ...<Widget>[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: answer.riskLevel.color.withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: answer.riskLevel.color.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    Icons.priority_high_rounded,
                    size: 17,
                    color: answer.riskLevel.color,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      answer.warning!,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.55,
                        fontWeight: FontWeight.w600,
                        color: answer.riskLevel.color,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // 正文
          Text(
            answer.answer,
            style: const TextStyle(fontSize: 14.5, height: 1.7),
          ),

          // 可执行步骤
          if (answer.steps.isNotEmpty) ...<Widget>[
            const SizedBox(height: 14),
            Text(
              '具体步骤',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            for (int i = 0; i < answer.steps.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Container(
                      width: 20,
                      height: 20,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${i + 1}',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Text(
                          answer.steps[i],
                          style: const TextStyle(fontSize: 14, height: 1.6),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],

          // 来源引用（V2.0 RAG 填充）
          if (answer.sources.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 9),
            Text(
              '参考来源',
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 5),
            for (final String s in answer.sources)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  '· $s',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 输入栏
// ---------------------------------------------------------------------------

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.onSend,
    this.enabled = true,
  });

  final TextEditingController controller;
  final void Function([String? preset]) onSend;

  /// 等待回答期间置为 false：按钮变灰，回车也不再触发发送
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(kPagePadding, 10, kPagePadding, 12),
      decoration: BoxDecoration(
        color: kSurfaceColor,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) {
                  if (enabled) onSend();
                },
                decoration: const InputDecoration(
                  hintText: '描述你的安全问题…',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 9),
            SizedBox(
              width: 46,
              height: 46,
              child: FilledButton(
                onPressed: enabled ? () => onSend() : null,
                style: FilledButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(46, 46),
                ),
                child: const Icon(Icons.arrow_upward_rounded, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 等待 AI 回答时的占位气泡。
///
/// 必须和「已经拿到回答」在视觉上区分开 ——
/// 让用户看着一个空白气泡猜「是卡住了还是没回答」是糟糕的体验。
class _ThinkingBubble extends StatelessWidget {
  const _ThinkingBubble();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 14, right: 32),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kSurfaceColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const SizedBox(
            width: 15,
            height: 15,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Text(
            '正在思考…',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
