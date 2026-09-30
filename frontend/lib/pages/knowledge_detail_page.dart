import 'package:flutter/material.dart';

import '../core/app_constants.dart';
import '../core/app_theme.dart';
import '../core/auth_controller.dart';
import '../models/knowledge_item.dart';
import '../services/api_client.dart';
import '../services/favorite_api.dart';
import '../services/knowledge_api.dart';
import '../widgets/async_status.dart';
import '../widgets/risk_badge.dart';
import 'login_page.dart';

/// 安知 —— 知识详情页（阶段 10 / 阶段 11b 加收藏）
///
/// 链路：`GET /api/knowledge/{id}` → 正文；打开后另发一次
/// `POST /api/knowledge/{id}/view` 记一次浏览；右上角收藏按钮走
/// `POST / DELETE /api/favorites`。
///
/// 浏览计数与详情**分成两个接口**是刻意的：读详情是幂等的，
/// 计数是一次写操作。若把计数塞进详情接口，浏览器的预取、
/// 失败重试、爬虫都会各算一次浏览。
///
/// 收藏状态则由详情接口顺带返回（`is_favorited`）——
/// 详情页本来就要发这一个请求，把按钮的初始状态捎回来，
/// 省掉一次往返。匿名访问时它恒为 `false`。
class KnowledgeDetailPage extends StatefulWidget {
  const KnowledgeDetailPage({
    super.key,
    required this.knowledgeId,
    this.preview,
    this.api,
    this.favoriteApi,
  });

  final int knowledgeId;

  /// 列表页点进来时带过来的那一条。
  ///
  /// 它只有标题、摘要、分类、风险等级，没有正文 —— 但足够把页头先画出来，
  /// 用户点进来立刻看到自己点的东西，而不是一个整页的转圈。
  final KnowledgeItem? preview;

  /// 允许注入，便于测试用假后端替换真实网络
  final KnowledgeApi? api;

  /// 收藏接口。生产路径下从 [AuthScope] 取，测试时注入。
  final FavoriteApi? favoriteApi;

  @override
  State<KnowledgeDetailPage> createState() => _KnowledgeDetailPageState();
}

class _KnowledgeDetailPageState extends State<KnowledgeDetailPage> {
  KnowledgeApi? _api;

  /// 为 `null` 表示当前拿不到收藏接口（没有 AuthScope）。
  /// 此时**不显示收藏按钮** —— 放一个点了没反应的图标比没有更糟。
  FavoriteApi? _favorites;

  /// 自建的匿名 client 要自己关；借用 `AuthController` 的则**不能关**
  /// （那是它持有的 client，关了会波及所有共用它的页面）。
  bool _ownsApi = false;
  bool _started = false;

  KnowledgeItem? _item;
  String? _error;
  bool _loading = true;
  bool _favoriteBusy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 只解析一次。放在这里而不是 initState：AuthScope 要通过 context 取，
    // 而 initState 阶段还读不到 InheritedWidget。
    if (_started) return;
    _started = true;

    final AuthController? auth = AuthScope.maybeOf(context);

    if (widget.api != null) {
      _api = widget.api;
    } else if (auth != null) {
      // 借用 AuthController 那个已接好鉴权头的客户端：详情接口要靠它
      // 带上 token，才知道当前用户有没有收藏这一条。
      _api = KnowledgeApi(client: auth.apiClient);
    } else {
      // 没有 AuthScope（单独 pump 这个页面）时退化成匿名请求
      _api = KnowledgeApi();
      _ownsApi = true;
    }

    _favorites = widget.favoriteApi ?? auth?.favoriteApi;
    _load();
  }

  @override
  void dispose() {
    if (_ownsApi) _api?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final KnowledgeItem item =
          await _api!.fetchKnowledgeDetail(widget.knowledgeId);
      if (!mounted) return;
      setState(() {
        _item = item;
        _loading = false;
      });
      _recordView();
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    }
  }

  /// 记一次浏览。**拿到正文之后才发** —— 加载失败时不该计数。
  ///
  /// 失败不提示：浏览量是锦上添花的数据，
  /// 让它把一次正常的阅读变成错误页是本末倒置。
  void _recordView() {
    _api!.recordView(widget.knowledgeId).then((int? count) {
      if (count == null || !mounted) return;
      setState(() => _item = _item?.copyWith(viewCount: count));
    });
  }

  // -------------------------------------------------------------------------
  // 收藏
  // -------------------------------------------------------------------------

  Future<void> _toggleFavorite() async {
    if (_favoriteBusy || _item == null || _favorites == null) return;

    final AuthController? auth = AuthScope.maybeOf(context);

    if (auth?.isLoggedIn != true) {
      final bool loggedIn = await _openLogin();
      if (!loggedIn || !mounted) return;

      // 登录后必须重新取一次详情：`is_favorited` 是**按人算**的，
      // 登录前拿到的那个 false 只代表「不知道你是谁」，不能当依据。
      await _load();
      if (!mounted) return;

      // 这个账号原来就收藏过 —— 用户想要的结果已经达成，不必再发一次请求。
      if (_item?.isFavorited == true) return;
      await _applyFavorite(true);
      return;
    }

    await _applyFavorite(!(_item?.isFavorited ?? false));
  }

  /// 打开登录页，返回是否登录成功。
  ///
  /// 未登录时点收藏直接推登录页，而不是弹一句「请先登录」就没了 ——
  /// 用户点这一下的意图是明确的，直接给他入口比让他自己回头找要顺手。
  Future<bool> _openLogin() async {
    final AuthController? auth = AuthScope.maybeOf(context);
    if (auth == null) return false;

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const LoginPage()),
    );
    return auth.isLoggedIn;
  }

  /// 真正发请求。
  ///
  /// **不做乐观更新**：先把图标翻过去、失败了再翻回来，用户会看到
  /// 一个「明明点成功了却又自己变回去」的按钮，比等半秒更让人不安。
  /// 这里如实等后端返回，期间按钮置灰。
  Future<void> _applyFavorite(bool want) async {
    final FavoriteApi api = _favorites!;
    final int id = widget.knowledgeId;

    setState(() => _favoriteBusy = true);
    try {
      if (want) {
        await api.add(id);
      } else {
        await api.remove(id);
      }
      if (!mounted) return;
      setState(() {
        _favoriteBusy = false;
        _item = _item?.copyWith(isFavorited: want);
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _favoriteBusy = false);
      // 失败必须说出来。图标老老实实停在原来的状态，
      // 不提示的话用户会以为收藏成功了。
      _toast(error.message);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackgroundColor,
      appBar: AppBar(
        title: const Text('知识详情'),
        actions: <Widget>[
          // 正文加载出来之前不显示：`is_favorited` 还没到手，
          // 先画一个「未收藏」的图标等于给了一个可能错的答案。
          if (_item != null && _favorites != null) _buildFavoriteButton(),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildFavoriteButton() {
    final bool favorited = _item?.isFavorited ?? false;
    final ThemeData theme = Theme.of(context);

    return IconButton(
      onPressed: _favoriteBusy ? null : _toggleFavorite,
      tooltip: favorited ? '取消收藏' : '收藏',
      icon: Icon(
        favorited ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
      ),
      color: favorited ? theme.colorScheme.primary : null,
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return Column(
        children: <Widget>[
          // 用列表页带过来的信息先把页头撑起来，避免整页空白
          if (widget.preview != null) _Header(item: widget.preview!),
          const Expanded(child: LoadingPlaceholder(message: '正在加载正文…')),
        ],
      );
    }

    if (_error != null) {
      return ErrorPlaceholder(
        message: _error!,
        hint: '这条内容可能已被下架，或链接有误。',
        onRetry: _load,
      );
    }

    final KnowledgeItem item = _item!;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _Header(item: item),
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(
              kPagePadding,
              0,
              kPagePadding,
              kPagePadding,
            ),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: kSurfaceColor,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _Summary(text: item.summary),
                const SizedBox(height: 16),
                _Content(text: item.content),
                if (item.source != null && item.source!.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 20),
                  _SourceLine(label: '来源', value: item.source!),
                ],
                if (item.author != null && item.author!.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 6),
                  _SourceLine(label: '作者', value: item.author!),
                ],
                const SizedBox(height: 20),
                const _Disclaimer(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 页头：标题 + 分类 + 风险等级 + 浏览量
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({required this.item});

  final KnowledgeItem item;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final SafetyCategory? category = item.category;

    return Padding(
      padding: const EdgeInsets.fromLTRB(kPagePadding, 18, kPagePadding, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            item.title,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              if (category != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(category.icon,
                        size: 15, color: theme.colorScheme.primary),
                    const SizedBox(width: 5),
                    Text(
                      category.name,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              RiskBadge(level: item.riskLevel, compact: true),
              _Meta(text: '${item.viewCount} 次浏览'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(fontSize: 11.5, color: Theme.of(context).colorScheme.outline),
    );
  }
}

// ---------------------------------------------------------------------------
// 正文各段
// ---------------------------------------------------------------------------

/// 摘要 —— 列表页展示的就是它，详情页置顶加粗，方便快速判断要不要细读
class _Summary extends StatelessWidget {
  const _Summary({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F6FA),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 13.5, height: 1.65),
      ),
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    // 正文为空时如实说明，而不是渲染一片空白让人以为没加载出来
    if (text.isEmpty) {
      return const Text(
        '这条内容暂时没有正文。',
        style: TextStyle(fontSize: 14, color: Color(0xFF9AA4B2)),
      );
    }

    return Text(
      text,
      style: const TextStyle(fontSize: 15, height: 1.85),
    );
  }
}

class _SourceLine extends StatelessWidget {
  const _SourceLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final Color muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 40,
          child: Text(
            label,
            style: TextStyle(fontSize: 12, color: muted),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(fontSize: 12.5, height: 1.5, color: muted),
          ),
        ),
      ],
    );
  }
}

/// 知识卡片同样带免责声明。
///
/// AI 问答页的高风险回答已经强制带警告，知识卡片却没有 ——
/// 而用户完全可能只看卡片、不问 AI。
class _Disclaimer extends StatelessWidget {
  const _Disclaimer();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF6E5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFFE0A3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(
            Icons.info_outline_rounded,
            size: 16,
            color: Color(0xFFB26A00),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '以上内容仅供参考。遇到紧急危险，请立即拨打 '
              '119 / 120 / 110，不要因为查资料而延误处置。',
              style: const TextStyle(
                fontSize: 12,
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
