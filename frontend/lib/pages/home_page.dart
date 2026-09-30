import 'package:flutter/material.dart';

import '../core/app_constants.dart';
import '../core/app_theme.dart';
import '../core/auth_controller.dart';
import '../core/open_after_login.dart';
import '../models/knowledge_item.dart';
import '../models/paged_result.dart';
import '../models/post_item.dart';
import '../models/user_settings.dart';
import '../services/api_client.dart';
import '../services/knowledge_api.dart';
import '../services/post_api.dart';
import '../services/settings_api.dart';
import '../widgets/async_status.dart';
import '../widgets/category_grid.dart';
import '../widgets/knowledge_tile.dart';
import '../widgets/risk_badge.dart';
import '../widgets/section_header.dart';
import 'knowledge_detail_page.dart';
import 'settings_home_page.dart';
import 'settings_notify_page.dart';

/// 安知 —— 首页
///
/// 模块顺序严格遵循 PROJECT_SPEC.md 第七节：
///   顶部 → 今日安全知识 → 推荐知识卡片 → 安全分类 → AI 助手入口 → 社区精选
///
/// 数据来源：
///   - 今日安全知识 / 推荐知识：`GET /api/knowledge`（取最新 5 条）
///   - 安全分类：本地常量 `kCategories`，与数据库种子数据一致
///     （图标与配色无法由 JSON 表达，故保留在客户端）
///   - 社区精选：`GET /api/posts`（阶段 12a 起接真实数据）
///   - 模块显隐与关注方向：`GET /api/settings`（阶段 13d）
///
/// **个性化只在登录后生效，而且只调顺序和显隐**：
///   - 关掉的模块不渲染（`GET /api/settings` 的 `home_modules`）
///   - 关注的领域排在知识列表前面（`prefer_categories`，阶段 13c）
///   - 设置拉不到时**按默认布局显示**，不把首页变成错误页 ——
///     首页的主体是安全知识，设置只是调整它的摆法
///
/// ⚠️ 尚未实现：`GET /api/home` 聚合接口（docs/API.md 第 9 节）。
/// 该接口能减少客户端请求数，但属于优化项而非必需项，
/// 目前由本页分别调用知识 / 帖子 / 设置三个接口。
class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    this.onNavigateToTab,
    this.api,
    this.postApi,
    this.settingsApi,
    this.isActive = true,
  });

  /// 请求切换到其他底部标签（如点击 AI 入口跳到 AI 页）
  final void Function(int index)? onNavigateToTab;

  /// 允许注入，便于测试用假客户端替换真实网络
  final KnowledgeApi? api;

  /// 社区精选用。与 [api] 分开注入：两者是不同模块，
  /// 其中一个挂了不该让另一个的测试也跟着难写。
  final PostApi? postApi;

  /// 个性化设置用。同样分开注入。
  final SettingsApi? settingsApi;

  /// 当前是否停留在首页这个标签。
  ///
  /// 底部导航用的是 `IndexedStack`，切换标签**不会重建页面** ——
  /// 没有这个信号的话，用户去「首页布局」关掉一个模块再回来，
  /// 看到的还是旧布局，只能靠下拉刷新，而界面上完全看不出这一点。
  final bool isActive;

  /// 底部导航索引：AI = 1，知识 = 2，社区 = 3
  static const int _tabAi = 1;
  static const int _tabKnowledge = 2;
  static const int _tabCommunity = 3;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final KnowledgeApi _api = widget.api ?? KnowledgeApi();
  late final bool _ownsApi = widget.api == null;

  late final PostApi _postApi = widget.postApi ?? PostApi();
  late final bool _ownsPostApi = widget.postApi == null;

  late final SettingsApi? _settingsApi =
      widget.settingsApi ?? AuthScope.maybeOf(context)?.settingsApi;

  /// **未登录或没拉到时是 null**，此时按默认布局显示、不做偏好排序。
  UserSettings? _settings;

  bool _started = false;
  bool _loggedIn = false;

  /// 首页只需要「今日 1 条 + 推荐 4 条」，多取一条留出余量
  static const int _fetchSize = 5;

  bool _loading = true;
  String? _error;
  List<KnowledgeItem> _items = const <KnowledgeItem>[];

  /// 社区精选。与知识分开记录状态：它是首页的次要模块，
  /// 拉不到时只在这一小块说明，不该让整个首页变成错误页。
  bool _postsLoading = true;
  bool _postsFailed = false;
  List<PostItem> _posts = const <PostItem>[];

  /// 首页的社区精选只露几条，点「进入社区」看全部
  static const int _previewPostCount = 3;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // 在 didChangeDependencies 里读而非 initState：
    // `AuthScope.maybeOf` 要读 InheritedWidget，initState 里读会被框架断言拦下。
    final bool loggedIn = AuthScope.maybeOf(context)?.isLoggedIn ?? false;

    if (!_started) {
      _started = true;
      _loggedIn = loggedIn;
      _load();
      return;
    }

    // 登录 / 退出之后设置换了账号，首页的布局和顺序都得跟着换
    if (loggedIn != _loggedIn) {
      _loggedIn = loggedIn;
      _load(showLoading: false);
    }
  }

  @override
  void didUpdateWidget(HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 从别的标签切回首页。刷新时**不显示加载态** ——
    // 内容本来就在，切个标签闪一下转圈比看到旧数据还难受。
    if (!oldWidget.isActive && widget.isActive) _load(showLoading: false);
  }

  @override
  void dispose() {
    if (_ownsApi) _api.dispose();
    if (_ownsPostApi) _postApi.dispose();
    super.dispose();
  }

  void _goTo(int index) => widget.onNavigateToTab?.call(index);

  /// 取个性化设置。
  ///
  /// **任何失败都只是让 `_settings` 保持 null**，不向上抛：
  /// 首页该做的是照常把知识显示出来，而不是因为一次设置请求失败
  /// 就变成错误页。未登录时干脆不发 —— 没有账号就没有设置，
  /// 发出去只会拿到 401，而现象看起来像是后端坏了。
  Future<void> _loadSettings() async {
    final SettingsApi? api = _settingsApi;
    if (api == null || !_loggedIn) {
      _settings = null;
      return;
    }

    try {
      _settings = await api.fetch();
    } on ApiException {
      _settings = null;
    }
  }

  Future<void> _load({bool showLoading = true}) async {
    if (showLoading && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    // 先取设置：关注的领域要作为 `prefer_categories` 一起发给知识接口，
    // 拿到之前没法定排序。这一步未登录时是空操作，不产生请求。
    await _loadSettings();

    try {
      final PagedResult<KnowledgeItem> result = await _api.fetchKnowledge(
        pageSize: _fetchSize,
        preferCategoryIds: _settings?.followedCategories,
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = null;
        _items = result.items;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.message;
        _items = const <KnowledgeItem>[];
      });
    }

    await _loadPosts(showLoading: showLoading);
  }

  /// 拉社区精选。
  ///
  /// **失败不写进 `_error`。** 知识才是首页的主体，社区精选是末尾的
  /// 一小块 —— 让它把整页变成错误页是本末倒置。这里单独记一个标志，
  /// 只影响那一块，并如实说明拉不到而不是显示空。
  Future<void> _loadPosts({bool showLoading = true}) async {
    if (showLoading && mounted) setState(() => _postsLoading = true);

    try {
      final PagedResult<PostItem> result = await _postApi.fetchPosts(
        pageSize: _previewPostCount,
      );
      if (!mounted) return;
      setState(() {
        _postsLoading = false;
        _postsFailed = false;
        _posts = result.items;
      });
    } on ApiException {
      if (!mounted) return;
      setState(() {
        _postsLoading = false;
        _postsFailed = true;
        _posts = const <PostItem>[];
      });
    }
  }

  /// 某个模块是否显示。
  ///
  /// 未登录或设置没拉到时一律显示：默认形态应该是「全都能看到」，
  /// 而不是因为一次网络抖动把首页清空。
  bool _showsModule(HomeModule module) =>
      _settings?.showsModule(module.id) ?? true;

  Future<void> _openHomeLayout() async {
    await openAfterLogin(context, () => const SettingsHomePage());
    if (!mounted) return;
    await _load(showLoading: false);
  }

  Future<void> _openNotify() async {
    await openAfterLogin(context, () => const SettingsNotifyPage());
    if (!mounted) return;
    await _load(showLoading: false);
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> blocks = _buildBlocks();

    return Scaffold(
      backgroundColor: kBackgroundColor,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              kPagePadding,
              8,
              kPagePadding,
              24,
            ),
            children: <Widget>[
              _HomeHeader(onOpenNotify: _openNotify),
              const SizedBox(height: 18),

              // 模块之间的间距在这里统一给：某个模块被关掉之后，
              // 不会在它原来的位置留下一个空当
              for (int i = 0; i < blocks.length; i++) ...<Widget>[
                if (i > 0) const SizedBox(height: 22),
                blocks[i],
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 首页各个模块，按 PROJECT_SPEC 第七节的顺序，跳过被关掉的那些。
  List<Widget> _buildBlocks() {
    final List<HomeModule> visible = <HomeModule>[
      for (final HomeModule module in HomeModule.all)
        if (_showsModule(module)) module,
    ];

    if (visible.isEmpty) {
      return <Widget>[_AllModulesHidden(onOpenLayout: _openHomeLayout)];
    }

    return <Widget>[
      // ① 今日安全知识 + ② 推荐知识
      ..._buildKnowledgeSections(),
      // ③ 安全分类
      if (visible.contains(HomeModule.category))
        Column(
          children: <Widget>[
            SectionHeader(
              title: '安全分类',
              subtitle: '六大领域，系统学习',
              icon: Icons.grid_view_rounded,
              actionLabel: '全部',
              onAction: () => _goTo(HomePage._tabKnowledge),
            ),
            CategoryGrid(
              onCategoryTap: (_) => _goTo(HomePage._tabKnowledge),
            ),
          ],
        ),
      // ④ AI 助手入口
      if (visible.contains(HomeModule.ai))
        _AiEntryCard(onTap: () => _goTo(HomePage._tabAi)),
      // ⑤ 社区精选
      if (visible.contains(HomeModule.community))
        Column(
          children: <Widget>[
            SectionHeader(
              title: '社区精选',
              subtitle: '看看大家在讨论什么',
              icon: Icons.forum_outlined,
              actionLabel: '进入社区',
              onAction: () => _goTo(HomePage._tabCommunity),
            ),
            _CommunityPreview(
              posts: _posts,
              loading: _postsLoading,
              failed: _postsFailed,
              onTap: () => _goTo(HomePage._tabCommunity),
            ),
          ],
        ),
    ];
  }

  /// ① 今日安全知识 + ② 推荐知识
  ///
  /// 三种状态分开渲染：加载中、加载失败（可重试）、后端暂无已发布内容。
  /// 失败时只影响这两块，分类 / AI 入口 / 社区仍可正常使用。
  ///
  /// 两块都关掉时返回空列表：知识拉没拉到都不影响首页剩下的部分，
  /// 没必要为一个用户已经藏起来的模块显示错误或空白。
  List<Widget> _buildKnowledgeSections() {
    final bool daily = _showsModule(HomeModule.daily);
    final bool recommend = _showsModule(HomeModule.recommend);
    if (!daily && !recommend) return const <Widget>[];

    if (_loading) {
      return const <Widget>[LoadingPlaceholder(message: '正在加载今日安全知识…')];
    }

    if (_error != null) {
      return <Widget>[
        ErrorPlaceholder(
          message: _error!,
          hint: '首页内容来自后端服务，请确认后端已启动',
          onRetry: _load,
        ),
      ];
    }

    if (_items.isEmpty) {
      return const <Widget>[
        EmptyPlaceholder(
          icon: Icons.menu_book_outlined,
          title: '暂无知识内容',
          message: '知识内容需经人工审核后才对外发布，\n审核完成前首页会保持为空。',
        ),
      ];
    }

    // 今日那条被今日卡片拿走后，剩下的才是推荐。
    // 今日整块关掉时不必白扔一条：这个位置本来就只有 5 条。
    final List<KnowledgeItem> recommended =
        daily && _items.length > 1 ? _items.sublist(1) : _items;

    return <Widget>[
      if (daily)
        _DailyKnowledgeCard(
          item: _items.first,
          // 首页卡片直接把条目带过去，详情页不必再从列表里找一遍
          onTap: () => _openDetail(_items.first),
        ),
      if (recommend && recommended.isNotEmpty) ...<Widget>[
        SectionHeader(
          title: '推荐知识',
          subtitle: '根据你的关注方向推荐',
          icon: Icons.recommend_outlined,
          actionLabel: '更多',
          onAction: () => _goTo(HomePage._tabKnowledge),
        ),
        _RecommendList(
          items: recommended,
          onTap: (KnowledgeItem item) => _openDetail(item),
        ),
      ],
    ];
  }

  void _openDetail(KnowledgeItem item) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => KnowledgeDetailPage(
          knowledgeId: item.id,
          preview: item,
          api: widget.api,
        ),
      ),
    );
  }
}

/// 五个模块全被关掉时的说明。
///
/// 不能只留一片空白：用户会以为首页坏了。要给出一条回去打开模块的路，
/// 而且必须说清「是你自己关的」，否则他只会觉得这个 App 出了问题。
class _AllModulesHidden extends StatelessWidget {
  const _AllModulesHidden({required this.onOpenLayout});

  final VoidCallback onOpenLayout;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        const EmptyPlaceholder(
          icon: Icons.dashboard_customize_outlined,
          title: '首页模块都被关掉了',
          message: '你在「首页布局」里关掉了全部模块，\n所以这里没有内容可以显示。',
        ),
        OutlinedButton(
          onPressed: onOpenLayout,
          child: const Text('去首页布局打开'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 顶部
// ---------------------------------------------------------------------------

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.onOpenNotify});

  final VoidCallback onOpenNotify;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Row(
      children: <Widget>[
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.shield_moon_outlined,
            color: Colors.white,
            size: 24,
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                kAppName,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: 22,
                ),
              ),
              Text(
                kAppSlogan,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: onOpenNotify,
          icon: const Icon(Icons.notifications_none_rounded),
          tooltip: '通知设置',
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// ① 今日安全知识
// ---------------------------------------------------------------------------

class _DailyKnowledgeCard extends StatelessWidget {
  const _DailyKnowledgeCard({required this.item, this.onTap});

  final KnowledgeItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Material(
      borderRadius: BorderRadius.circular(16),
      color: theme.colorScheme.primary,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Expanded(
                    child: Row(
                      children: <Widget>[
                        Icon(
                          Icons.wb_sunny_outlined,
                          size: 16,
                          color: Colors.white70,
                        ),
                        SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            '今日安全知识',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: Colors.white70,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  RiskBadge(level: item.riskLevel, compact: true),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                item.title,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  height: 1.35,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Text(
                item.summary,
                style: const TextStyle(
                  fontSize: 13,
                  color: Colors.white70,
                  height: 1.55,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  Text(
                    '查看详情',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.white.withValues(alpha: 0.95),
                    ),
                  ),
                  const SizedBox(width: 3),
                  const Icon(
                    Icons.arrow_forward_rounded,
                    size: 15,
                    color: Colors.white,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ② 推荐知识
// ---------------------------------------------------------------------------

class _RecommendList extends StatelessWidget {
  const _RecommendList({required this.items, this.onTap});

  final List<KnowledgeItem> items;

  /// 回调带上被点的那一条 —— 之前是无参的，只能「跳到知识页」，
  /// 现在要打开对应条目的详情，必须知道点的是谁。
  final void Function(KnowledgeItem item)? onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        for (int i = 0; i < items.length; i++) ...<Widget>[
          KnowledgeTile(
            item: items[i],
            onTap: onTap == null ? null : () => onTap!(items[i]),
          ),
          if (i != items.length - 1) const SizedBox(height: kCardGap),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// ④ AI 助手入口
// ---------------------------------------------------------------------------

class _AiEntryCard extends StatelessWidget {
  const _AiEntryCard({this.onTap});

  final VoidCallback? onTap;

  /// 示例问题：点击后应直接带入 AI 页面并提问。
  /// 目前仅作展示，接入 AI 页面后由回调传递。
  static const List<String> _examples = <String>[
    '宿舍发生火灾怎么办？',
    '电动车能在楼道充电吗？',
  ];

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: kSurfaceColor,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.auto_awesome,
                  size: 19,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'AI 安全助手',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      '有安全问题，随时问我',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final String q in _examples)
                ActionChip(
                  label: Text(q),
                  onPressed: onTap,
                  labelStyle: const TextStyle(fontSize: 12.5),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
/// 社区精选。
///
/// 数据来源 `GET /api/posts`（阶段 12a）。三种「没有内容」的情况
/// 必须分开说，但都只占这一小块 —— 社区是首页末尾的次要模块，
/// 不该因为它拉不到就把整个首页变成错误页：
///   · 加载中 → 一行转圈
///   · 拉不到 → 说明拉不到（**不是**「还没有人发帖」）
///   · 确实没有 → 「还没有人发帖」
class _CommunityPreview extends StatelessWidget {
  const _CommunityPreview({
    required this.posts,
    required this.loading,
    required this.failed,
    this.onTap,
  });

  final List<PostItem> posts;
  final bool loading;
  final bool failed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2.2),
          ),
        ),
      );
    }

    if (posts.isEmpty) {
      return _CommunityNotice(
        icon: failed ? Icons.cloud_off_rounded : Icons.forum_outlined,
        // 拉不到就老实说拉不到。写成「还没有人发帖」是在骗人 ——
        // 用户会以为社区是空的，实际是后端没连上。
        text: failed ? '社区内容暂时加载不出来' : '还没有人发帖，去发第一条吧',
        onTap: onTap,
      );
    }

    return Column(
      children: <Widget>[
        for (final PostItem post in posts)
          Padding(
            padding: const EdgeInsets.only(bottom: kCardGap),
            child: Material(
              color: kSurfaceColor,
              borderRadius: BorderRadius.circular(kCardRadius),
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(kCardRadius),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        post.title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 14.5,
                          height: 1.4,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: <Widget>[
                          Icon(
                            Icons.person_outline_rounded,
                            size: 13,
                            color: theme.colorScheme.outline,
                          ),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              post.authorName,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: theme.colorScheme.outline,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Icon(
                            Icons.favorite_border_rounded,
                            size: 13,
                            color: theme.colorScheme.outline,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '${post.likeCount}',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: theme.colorScheme.outline,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 13,
                            color: theme.colorScheme.outline,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '${post.commentCount}',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 社区精选没有内容时的一行说明（加载中 / 拉不到 / 确实为空共用）
class _CommunityNotice extends StatelessWidget {
  const _CommunityNotice({
    required this.icon,
    required this.text,
    this.onTap,
  });

  final IconData icon;
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Material(
      color: kSurfaceColor,
      borderRadius: BorderRadius.circular(kCardRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(kCardRadius),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(icon, size: 17, color: theme.colorScheme.outline),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
