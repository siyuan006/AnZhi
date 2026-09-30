import 'package:flutter/material.dart';

import '../core/app_constants.dart';
import '../core/app_theme.dart';
import '../core/auth_controller.dart';
import '../models/post_item.dart';
import '../services/api_client.dart';
import '../services/post_api.dart';

/// 安知 —— 发布帖子（阶段 12d，PROJECT_SPEC 第二十节）
///
/// 链路：`POST /api/posts`。需要登录。
///
/// 发布成功后 `Navigator.pop` 把新帖子带回上一页，由上一页决定
/// 怎么用它（社区页据此刷新列表）。本页不自己跳详情 ——
/// 那样返回时会连跳两级，用户会懵。
class PostComposePage extends StatefulWidget {
  const PostComposePage({super.key, this.api});

  /// 允许注入，便于测试用假后端替换真实网络
  final PostApi? api;

  @override
  State<PostComposePage> createState() => _PostComposePageState();
}

class _PostComposePageState extends State<PostComposePage> {
  /// 没注入时**借用 `AuthScope` 那个带 token 的客户端**，不自己造一个。
  ///
  /// 发帖是「这条帖子算谁的」的接口，匿名客户端只会拿到 401 ——
  /// 而且现象看起来完全像是后端的毛病。
  ///
  /// 在 `didChangeDependencies` 里取而不是 `initState`：`AuthScope.maybeOf`
  /// 要读 InheritedWidget，在 `initState` 里读会被框架断言拦下。
  PostApi? _api;
  bool _started = false;

  final TextEditingController _title = TextEditingController();
  final TextEditingController _content = TextEditingController();

  /// `null` 表示「不属于任何分类」。帖子允许没有分类，
  /// 因此不能强制用户选一个才能发。
  int? _categoryId;

  bool _submitting = false;

  /// 标题与正文的长度上限，与后端 `post_service` 保持一致。
  /// 两处不一致的话，用户会在本地被放过、到服务端才被拒。
  static const int _titleMax = 200;
  static const int _contentMax = 5000;

  @override
  void initState() {
    super.initState();
    // 两个输入框的可用状态依赖"填了没有"，每次输入都要重算按钮
    _title.addListener(_onChanged);
    _content.addListener(_onChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;

    _api = widget.api ?? PostApi(client: AuthScope.maybeOf(context)?.apiClient);
  }

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    // 只关自己 new 出来的那个；注入进来的由注入方负责
    if (widget.api == null) _api?.dispose();
    super.dispose();
  }

  void _onChanged() => setState(() {});

  bool get _canSubmit =>
      !_submitting &&
      _title.text.trim().isNotEmpty &&
      _content.text.trim().isNotEmpty;

  Future<void> _submit() async {
    final PostApi? api = _api;
    if (!_canSubmit || api == null) return;

    setState(() => _submitting = true);

    try {
      final PostItem created = await api.createPost(
        title: _title.text,
        content: _content.text,
        categoryId: _categoryId,
      );
      if (!mounted) return;
      Navigator.of(context).pop<PostItem>(created);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool loggedIn = AuthScope.maybeOf(context)?.isLoggedIn ?? false;

    return Scaffold(
      backgroundColor: kBackgroundColor,
      appBar: AppBar(
        title: const Text('发布帖子'),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(
              onPressed: _canSubmit ? _submit : null,
              child: _submitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('发布'),
            ),
          ),
        ],
      ),
      body: loggedIn
          ? _buildForm(theme)
          : _buildLoginNotice(theme),
    );
  }

  Widget _buildLoginNotice(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(kPagePadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.lock_outline_rounded,
              size: 34,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              '登录后才能发布帖子',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        kPagePadding,
        16,
        kPagePadding,
        kPagePadding,
      ),
      children: <Widget>[
        TextField(
          controller: _title,
          maxLength: _titleMax,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: '标题',
            hintText: '一句话说清楚你要分享什么',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _content,
          maxLines: 12,
          minLines: 6,
          maxLength: _contentMax,
          decoration: const InputDecoration(
            labelText: '正文',
            hintText: '把经过、做法或提醒写清楚，别人才能用得上',
            alignLabelWithHint: true,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          '分类（可不选）',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: 13.5,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final SafetyCategory category in kCategories)
              ChoiceChip(
                label: Text(category.name),
                selected: _categoryId == category.id,
                // 再点一下取消选择 —— 选错了要能退回「不选」，
                // 否则按错一次就只能强行归类
                onSelected: (bool selected) => setState(
                  () => _categoryId = selected ? category.id : null,
                ),
              ),
          ],
        ),
        const SizedBox(height: 18),
        Text(
          '发布后其他人就能在社区里看到。内容只代表你个人的经验，'
          '紧急情况请先拨打 110 / 119 / 120。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 12,
            height: 1.6,
          ),
        ),
      ],
    );
  }
}
