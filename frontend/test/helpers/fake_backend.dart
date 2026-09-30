import 'dart:convert';

import 'package:anzhi/core/app_constants.dart';
import 'package:anzhi/core/auth_controller.dart';
import 'package:anzhi/services/api_client.dart';
import 'package:anzhi/services/auth_api.dart';
import 'package:anzhi/services/auth_store.dart';
import 'package:anzhi/services/chat_api.dart';
import 'package:anzhi/services/favorite_api.dart';
import 'package:anzhi/services/history_api.dart';
import 'package:anzhi/services/post_api.dart';
import 'package:anzhi/services/knowledge_api.dart';
import 'package:anzhi/services/settings_api.dart';
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

  /// 各条目的浏览量。POST /view 自增，GET 详情时回填 ——
  /// 让「计数确实被写进去并被读到」这件事可以在测试里被观察到。
  final Map<int, int> viewCounts = <int, int>{};

  /// 设为 true 时模拟「连不上服务器」
  bool offline = false;

  /// 设为非空时，收藏接口一律返回该状态码。
  ///
  /// 收藏失败是一条**必须被看见**的路径：图标不许自己翻过去，
  /// 用户得知道这一下没生效。
  int? favoriteErrorStatus;
  String favoriteErrorMessage = '收藏失败，请稍后再试';

  /// 设为非空时，历史接口一律返回该状态码。
  int? historyErrorStatus;
  String historyErrorMessage = '浏览历史加载失败，请稍后再试';

  /// 非 2xx 响应
  int? errorStatus;
  Map<String, dynamic> errorBody = <String, dynamic>{'detail': '出错了'};

  /// 非 JSON 响应体（模拟打到了别的服务）
  String? rawBody;

  /// 响应延迟，用于验证超时分支
  Duration? delay;

  // --- 认证（/api/auth/*）-------------------------------------------------
  //
  // 假后端**不实现真正的认证**（不验签、不哈希）：
  // 它只需要让客户端相信「登录成功了」，从而驱动登录后的界面。
  // 验签与哈希由后端的测试负责 —— 那才是它们真正运行的地方。

  /// 已注册的账号：用户名 -> 密码
  final Map<String, String> accounts = <String, String>{};

  /// 用户名 -> 用户 id
  final Map<String, int> accountIds = <String, int>{};

  /// 设为非 null 时，`/api/auth/me` 返回该状态码（用于验证「token 已失效」）
  int? meErrorStatus;

  /// 依次收到的 Authorization 头，用来断言「token 确实带上了」
  final List<String?> authHeaders = <String?>[];

  /// 发出 token 时用的前缀，便于断言它确实是个 bearer token
  static const String _tokenPrefix = 'fake-token-for-';

  String _tokenFor(String username) => '$_tokenPrefix$username';

  int _idFor(String username) =>
      accountIds.putIfAbsent(username, () => accountIds.length + 1);

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
    'references': <Map<String, dynamic>>[],
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

  /// 认证接口。带上 [token] 读取回调，与生产路径一致 ——
  /// 请求头里会实时带上当前 token。
  AuthApi authApi({String? Function()? token}) => AuthApi(
        client: ApiClient(
          httpClient: httpClient,
          baseUrl: 'http://test.local',
          token: token,
        ),
      );

  /// 供页面测试注入的登录状态，连着一个假后端。
  ///
  /// 注入底层 http 客户端而不是 AuthApi：token 的接线由
  /// AuthController 自己负责，测试不必（也不应该）替它接一遍。
  ///
  /// 页面里的收藏接口是从 `AuthScope` 上取的 `authController.favoriteApi`，
  /// 因此注入这一个对象就同时打通了登录与收藏两条链路。
  AuthController authController({AuthStore? store}) => AuthController(
        httpClient: httpClient,
        baseUrl: 'http://test.local',
        store: store ?? MemoryAuthStore(),
      );

  /// 收藏接口（需要调用方自己给出 token 回调）。
  ///
  /// 页面测试一般不需要它 —— 那些用的是 `authController().favoriteApi`。
  /// 这个留给只测 `FavoriteApi` 本身的用例。
  FavoriteApi favoriteApi({String? Function()? token}) => FavoriteApi(
        client: ApiClient(
          httpClient: httpClient,
          baseUrl: 'http://test.local',
          token: token,
        ),
      );

  /// 浏览历史接口（需要调用方自己给出 token 回调）。
  /// 页面测试一般不需要它 —— 那些用的是 `authController().historyApi`。
  HistoryApi historyApi({String? Function()? token}) => HistoryApi(
        client: ApiClient(
          httpClient: httpClient,
          baseUrl: 'http://test.local',
          token: token,
        ),
      );

  /// 社区接口。
  ///
  /// 读不需要 token（帖子是公开内容），发评论需要 ——
  /// 所以 `token` 是可选的：不传就是「未登录」，发评论会拿到 401，
  /// 与服务端的行为一致。
  PostApi postApi({Duration? timeout, String? Function()? token}) => PostApi(
        client: ApiClient(
          httpClient: httpClient,
          baseUrl: 'http://test.local',
          timeout: timeout,
          token: token,
        ),
      );

  /// 个性化设置接口（需要调用方自己给出 token 回调）。
  ///
  /// 页面测试一般不需要它 —— 那些用的是 `authController().settingsApi`。
  /// 这个留给只测 `SettingsApi` 本身的用例。
  SettingsApi settingsApi({String? Function()? token}) => SettingsApi(
        client: ApiClient(
          httpClient: httpClient,
          baseUrl: 'http://test.local',
          token: token,
        ),
      );

  /// 预置一个已注册的账号
  void seedAccount(String username, String password, {String? nickname}) {
    accounts[username] = password;
    _idFor(username);
    nicknames[username] = nickname;
  }

  /// 用户名 -> 昵称
  final Map<String, String?> nicknames = <String, String?>{};

  // --- 收藏（/api/favorites）----------------------------------------------

  /// 用户名 -> 已收藏的知识 id，**按收藏先后**排列（最新的在最后）。
  /// 与真实后端一样，收藏是跟着账号走的 ——
  /// 「A 看不到 B 的收藏」这条必须在假后端里也成立，
  /// 否则页面测试就验不出越权读取。
  final Map<String, List<int>> favorites = <String, List<int>>{};

  /// 预置一条收藏（测试里直接构造「已经收藏过」的状态）
  void seedFavorite(String username, int knowledgeId) {
    favorites.putIfAbsent(username, () => <int>[]).add(knowledgeId);
  }

  // --- 浏览历史（/api/history）--------------------------------------------

  /// 用户名 -> 浏览过的知识 id，**按浏览先后**排列（最近看的在最后）。
  /// 同样跟着账号走，「A 看不到 B 的历史」必须在假后端里也成立。
  final Map<String, List<int>> histories = <String, List<int>>{};

  /// 「用户名/知识 id」 -> 距现在多久以前看的。
  ///
  /// 用来构造「三天前看过」这类状态；不设置就是刚刚看过的。
  final Map<String, Duration> _historyAges = <String, Duration>{};

  /// 预置一条浏览记录。
  void seedHistory(
    String username,
    int knowledgeId, {
    Duration age = Duration.zero,
  }) {
    histories.putIfAbsent(username, () => <int>[]).add(knowledgeId);
    _historyAges['$username/$knowledgeId'] = age;
  }

  /// 记一次浏览，与真实后端一样**同一篇只留一条**（时间往后推）。
  void _recordHistory(String username, int knowledgeId) {
    final List<int> ids = histories.putIfAbsent(username, () => <int>[]);
    ids
      ..remove(knowledgeId)
      ..add(knowledgeId);
    _historyAges['$username/$knowledgeId'] = Duration.zero;
  }

  // --- 社区帖子（/api/posts）----------------------------------------------

  /// 帖子目录，与真实后端一样按发布时间倒序返回（最新的在前）。
  ///
  /// 默认给两条，且**刻意带一个没有分类的**：帖子可以不属于任何分类
  /// 是真实存在的情况（数据库里 `category_id` 可空），
  /// 假后端只给有分类的帖子的话，界面漏处理这一支也测不出来。
  List<Map<String, dynamic>> posts = <Map<String, dynamic>>[
    <String, dynamic>{
      'id': 1,
      'title': '宿舍用电的几点提醒',
      'summary': '不要在一个插排上同时接大功率电器。',
      'content': '不要在一个插排上同时接大功率电器，电线过热是宿舍火灾最常见的原因。',
      'category_id': 2,
      'author': <String, dynamic>{'id': 1, 'name': '小艾'},
      'like_count': 3,
      'comment_count': 1,
      'created_at': '2026-09-30T10:00:00',
    },
    <String, dynamic>{
      'id': 2,
      'title': '遇到诈骗电话我是这么处理的',
      'summary': '挂掉，打 96110，把号码报给家人。',
      'content': '挂掉，打 96110，把号码报给家人，让他们也留意。',
      'category_id': null,
      'author': <String, dynamic>{'id': 2, 'name': '匿名同学'},
      'like_count': 5,
      'comment_count': 0,
      'created_at': '2026-09-29T10:00:00',
    },
  ];

  /// 预置一条帖子，返回它的 id。
  ///
  /// 不传 `category_id` 就是「不属于任何分类」。
  ///
  /// [owner] 是发帖人的**用户名**（不是署名昵称）——「我的帖子」
  /// 与删帖的权限判断都以它为准，与真实后端按 `user_id` 过滤一致。
  int seedPost({
    required String title,
    String content = '正文。',
    int? categoryId,
    String author = '小艾',
    String owner = 'alice',
    int likeCount = 0,
    int commentCount = 0,
    String createdAt = '2026-09-30T12:00:00',
  }) {
    final int id = _nextPostId++;
    postOwners[id] = owner;
    posts = <Map<String, dynamic>>[
      <String, dynamic>{
        'id': id,
        'title': title,
        'summary': content,
        'content': content,
        'category_id': categoryId,
        'author': <String, dynamic>{'id': 1, 'name': author},
        'like_count': likeCount,
        'comment_count': commentCount,
        'created_at': createdAt,
      },
      ...posts,
    ];
    return id;
  }

  /// 下一个可用的帖子 id。
  ///
  /// **不能用 `posts.length + 1`**：帖子会被删掉，删完再发新的就会
  /// 撞上一条已经存在的 id。真实后端的自增主键也不会回收已删的号。
  int _nextPostId = 3;

  /// 帖子 id -> 发帖人的用户名
  final Map<int, String> postOwners = <int, String>{1: 'alice', 2: 'bob'};

  /// 清空帖子目录（测「还没有人发帖」用）
  void seedNoPosts() => posts = <Map<String, dynamic>>[];

  /// 强制**发帖**走错误分支（例如 422 校验失败）。
  ///
  /// 不复用全局的 `errorStatus`：那会把帖子列表一起打挂，
  /// 于是「发帖失败」和「页面没加载出来」在测试里长得一模一样。
  int? postCreateStatus;
  String postCreateError = '标题不能为空';

  /// 强制**删帖**走错误分支（例如 403 只能删自己的）。
  int? postDeleteStatus;
  String postDeleteError = '只能删除自己的帖子';

  /// 依次收到的发帖请求体。
  ///
  /// 服务层测试里断言过「没选分类时 `category_id` 传的是 null」，
  /// 那只证明了 `PostApi` 的行为；页面这一层要证明的是
  /// 「用户在界面上选的那个分类，确实一路传到了请求体里」——
  /// 中间任何一环写死成 null，都只有在这里才看得出来。
  final List<Map<String, dynamic>> postCreateRequests =
      <Map<String, dynamic>>[];

  // --- 点赞（/api/posts/{id}/like）-----------------------------------------

  /// 用户名 -> 点过赞的帖子 id。
  ///
  /// 与真实后端一样**跟着账号走**：「A 点的赞不会让 B 的爱心变亮」
  /// 这条必须在假后端里也成立，否则页面测试验不出这个 bug。
  final Map<String, Set<int>> likes = <String, Set<int>>{};

  /// 预置一个「已经点过」的状态
  void seedLike(String username, int postId) {
    likes.putIfAbsent(username, () => <int>{}).add(postId);
  }

  /// 强制点赞走错误分支。
  ///
  /// 不复用全局的 `errorStatus`：那会把帖子列表一起打挂，
  /// 于是「点赞失败」和「页面没加载出来」在测试里长得一模一样。
  int? likeStatus;
  String likeError = '点赞失败，请稍后再试';

  /// 帖子目录里的 `like_count` 是**别人**点的赞，这里再叠上假用户点的。
  /// 与真实后端一致：数字来自真实的行数，不是「旧值加一」。
  int _likeCountOf(Map<String, dynamic> post) {
    final int base = (post['like_count'] as num?)?.toInt() ?? 0;
    final int mine = likes.values
        .where((Set<int> ids) => ids.contains(post['id']))
        .length;
    return base + mine;
  }

  /// 按**当前请求者**的视角序列化一条帖子。
  ///
  /// 真实后端就是这么做的：列表与详情都带 `is_liked`，
  /// 匿名请求恒为 false。
  Map<String, dynamic> _postJson(Map<String, dynamic> post, String? viewer) {
    return <String, dynamic>{
      ...post,
      'like_count': _likeCountOf(post),
      'is_liked': viewer != null &&
          (likes[viewer] ?? const <int>{}).contains(post['id']),
    };
  }

  Map<String, dynamic> _postSummaryJson(
    Map<String, dynamic> post,
    String? viewer,
  ) {
    // 与真实后端一致：列表项**不带 content**，只有 summary
    final Map<String, dynamic> copy = Map<String, dynamic>.from(
      _postJson(post, viewer),
    )..remove('content');
    return copy;
  }

  Map<String, dynamic> _postPage(Map<String, String> query, String? viewer) {
    Iterable<Map<String, dynamic>> list = posts;

    final String? keyword = query['keyword'];
    if (keyword != null && keyword.isNotEmpty) {
      list = list.where(
        (Map<String, dynamic> p) =>
            '${p['title']}'.contains(keyword) ||
            '${p['content']}'.contains(keyword),
      );
    }

    final int? categoryId = int.tryParse(query['category_id'] ?? '');
    if (categoryId != null) {
      list = list.where((Map<String, dynamic> p) => p['category_id'] == categoryId);
    }

    final List<Map<String, dynamic>> all = list.toList();
    final int page = int.tryParse(query['page'] ?? '1') ?? 1;
    final int pageSize = int.tryParse(query['page_size'] ?? '20') ?? 20;
    final int start = (page - 1) * pageSize;
    final List<Map<String, dynamic>> slice = start >= all.length
        ? const <Map<String, dynamic>>[]
        : all.sublist(start, (start + pageSize).clamp(0, all.length));

    return <String, dynamic>{
      'total': all.length,
      'page': page,
      'page_size': pageSize,
      'items': slice.map((Map<String, dynamic> p) => _postSummaryJson(p, viewer)).toList(),
    };
  }

  Future<http.Response> _handlePosts(http.Request request, String path) async {
    final String? viewer = _usernameFromHeader(request);

    if (path == '/api/posts') {
      if (request.method == 'POST') {
        return _handlePostCreate(request, viewer);
      }
      return _json(_postPage(request.url.queryParameters, viewer), 200);
    }

    // `/mine` 必须在下面 `int.tryParse(rest)` 之前处理 ——
    // 真实后端那边也是一条路由顺序的硬性要求（`/mine` 要声明在
    // `/{post_id}` 前面，否则会被当成 id 解析失败）。假后端先解析
    // 成 int 的话，`/mine` 会变成 404，而真实后端给的是 401，
    // 于是页面测试和线上行为对不上。
    if (path == '/api/posts/mine') {
      return _handleMyPosts(request, viewer);
    }

    final String rest = path.substring('/api/posts/'.length);
    if (rest.endsWith('/comments')) {
      final int? postId =
          int.tryParse(rest.substring(0, rest.length - '/comments'.length));
      return _handleComments(request, postId);
    }
    if (rest.endsWith('/like')) {
      final int? postId =
          int.tryParse(rest.substring(0, rest.length - '/like'.length));
      return _handleLike(request, postId);
    }

    final int? id = int.tryParse(rest);

    if (request.method == 'DELETE') {
      return _handlePostDelete(id, viewer);
    }

    final Map<String, dynamic>? post = _findPost(id);

    if (post == null) {
      return _json(<String, dynamic>{'detail': '帖子不存在或已删除'}, 404);
    }
    return _json(_postJson(post, viewer), 200);
  }

  /// 发帖。复述了后端的四个约定：
  ///   - 未登录一律 401「请先登录」
  ///   - 标题与正文按**去掉首尾空白之后**的文本判空（全空格算空）
  ///   - 分类不存在时 404 而不是 500
  ///   - 成功返回**详情结构**（含正文），状态码 201
  Future<http.Response> _handlePostCreate(
    http.Request request,
    String? viewer,
  ) async {
    if (postCreateStatus != null) {
      return _json(<String, dynamic>{'detail': postCreateError}, postCreateStatus!);
    }
    if (viewer == null) {
      return _json(<String, dynamic>{'detail': '请先登录'}, 401);
    }

    final Map<String, dynamic> body = _body(request);
    postCreateRequests.add(body);
    final String title = '${body['title'] ?? ''}'.trim();
    final String content = '${body['content'] ?? ''}'.trim();

    if (title.isEmpty) {
      return _json(<String, dynamic>{'detail': '标题不能为空'}, 422);
    }
    if (content.isEmpty) {
      return _json(<String, dynamic>{'detail': '正文不能为空'}, 422);
    }

    final int? categoryId = (body['category_id'] as num?)?.toInt();
    if (categoryId != null &&
        !kCategories.any((SafetyCategory c) => c.id == categoryId)) {
      return _json(<String, dynamic>{'detail': '分类不存在'}, 404);
    }

    // 标题压成一行 —— 与后端 `normalize_title` 一致
    final String normalized = title.replaceAll(RegExp(r'\s+'), ' ');
    final String name = nicknames[viewer] ?? viewer;
    final int id = _nextPostId++;
    postOwners[id] = viewer;

    final Map<String, dynamic> created = <String, dynamic>{
      'id': id,
      'title': normalized,
      'summary': content,
      'content': content,
      'category_id': categoryId,
      'author': <String, dynamic>{'id': _idFor(viewer), 'name': name},
      'like_count': 0,
      'comment_count': 0,
      'created_at': '2026-09-30T12:30:00',
    };
    posts = <Map<String, dynamic>>[created, ...posts];

    return _json(_postJson(created, viewer), 201);
  }

  /// 「我的帖子」。未登录 401；否则只返回自己发的，最新的在前。
  Future<http.Response> _handleMyPosts(
    http.Request request,
    String? viewer,
  ) async {
    if (viewer == null) {
      return _json(<String, dynamic>{'detail': '请先登录'}, 401);
    }

    final List<Map<String, dynamic>> mine = posts
        .where((Map<String, dynamic> p) => postOwners[p['id']] == viewer)
        .toList(growable: false);

    final Map<String, String> query = request.url.queryParameters;
    final int page = int.tryParse(query['page'] ?? '1') ?? 1;
    final int pageSize = int.tryParse(query['page_size'] ?? '20') ?? 20;
    final int start = (page - 1) * pageSize;
    final List<Map<String, dynamic>> slice = start >= mine.length
        ? const <Map<String, dynamic>>[]
        : mine.sublist(start, (start + pageSize).clamp(0, mine.length));

    return _json(<String, dynamic>{
      'total': mine.length,
      'page': page,
      'page_size': pageSize,
      'items': slice
          .map((Map<String, dynamic> p) => _postSummaryJson(p, viewer))
          .toList(),
    }, 200);
  }

  /// 删帖。复述了后端的三个约定：
  ///   - 未登录 401
  ///   - 删别人的 403 而不是 404（已发布的帖子人人看得见，
  ///     假装它不存在只会让作者困惑）
  ///   - 成功 204 且**没有响应体**
  Future<http.Response> _handlePostDelete(int? id, String? viewer) async {
    if (postDeleteStatus != null) {
      return _json(<String, dynamic>{'detail': postDeleteError}, postDeleteStatus!);
    }
    if (viewer == null) {
      return _json(<String, dynamic>{'detail': '请先登录'}, 401);
    }

    final Map<String, dynamic>? post = _findPost(id);
    if (post == null) {
      return _json(<String, dynamic>{'detail': '帖子不存在或已删除'}, 404);
    }
    if (postOwners[post['id']] != viewer) {
      return _json(<String, dynamic>{'detail': '只能删除自己的帖子'}, 403);
    }

    posts = posts.where((Map<String, dynamic> p) => p['id'] != id).toList();
    postOwners.remove(id);
    comments.remove(id);

    return http.Response('', 204);
  }

  /// 点赞与取消，复述了后端的三个关键约定：
  ///   - 未登录一律 401「请先登录」
  ///   - 新建时 201、之前就点过时 200（幂等）
  ///   - **回传当前状态**而不只是「成功」，客户端据此改数字和爱心
  Future<http.Response> _handleLike(http.Request request, int? postId) async {
    if (likeStatus != null) {
      return _json(<String, dynamic>{'detail': likeError}, likeStatus!);
    }

    final Map<String, dynamic>? post = _findPost(postId);
    if (post == null) {
      return _json(<String, dynamic>{'detail': '帖子不存在或已删除'}, 404);
    }

    final String? username = _usernameFromHeader(request);
    if (username == null) {
      return _json(<String, dynamic>{'detail': '请先登录'}, 401);
    }

    final Set<int> ids = likes.putIfAbsent(username, () => <int>{});
    final int id = post['id'] as int;

    if (request.method == 'DELETE') {
      ids.remove(id);
      return _json(<String, dynamic>{
        'like_count': _likeCountOf(post),
        'is_liked': false,
      }, 200);
    }

    final bool created = ids.add(id);
    return _json(<String, dynamic>{
      'like_count': _likeCountOf(post),
      'is_liked': true,
    }, created ? 201 : 200);
  }

  Map<String, dynamic>? _findPost(int? id) => id == null
      ? null
      : posts.cast<Map<String, dynamic>?>().firstWhere(
            (Map<String, dynamic>? p) => p!['id'] == id,
            orElse: () => null,
          );

  /// 评论按帖子 id 分组。
  ///
  /// 默认只给第一条帖子配评论：第一条覆盖「有评论」，
  /// 第二条覆盖「还没有人评论」—— 两种状态都要能测到。
  Map<int, List<Map<String, dynamic>>> comments =
      <int, List<Map<String, dynamic>>>{
    1: <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 1,
        'content': '补充一点：充电器长期插着也会发热。',
        'author': <String, dynamic>{'id': 3, 'name': '小周'},
        'created_at': '2026-09-30T11:00:00',
      },
    ],
  };

  void seedNoComments() => comments = <int, List<Map<String, dynamic>>>{};

  /// 强制**读评论**走错误分支（例如 500）。
  ///
  /// 只影响评论，不影响帖子本身 —— 这样才测得出「评论这一块挂了，
  /// 正文照常可读」。
  int? commentReadStatus;

  String? commentReadError;

  /// 强制**发评论**走错误分支。为 `null` 时按是否带 token 判断能否发表。
  int? commentPostStatus;

  String? commentPostError;

  /// 发出去的评论署名。
  String currentUserName = '我';

  /// 直接造一条评论，返回它的 id。
  int seedComment(
    int postId, {
    required String content,
    String author = '小周',
    String createdAt = '2026-09-30T11:00:00',
  }) {
    final List<Map<String, dynamic>> list =
        comments[postId] ?? <Map<String, dynamic>>[];
    final int id = list.length + 1;
    comments[postId] = <Map<String, dynamic>>[
      ...list,
      <String, dynamic>{
        'id': id,
        'content': content,
        'author': <String, dynamic>{'id': 3, 'name': author},
        'created_at': createdAt,
      },
    ];
    return id;
  }

  Future<http.Response> _handleComments(
    http.Request request,
    int? postId,
  ) async {
    final int? id = postId;
    if (id == null || _findPost(id) == null) {
      return _json(<String, dynamic>{'detail': '帖子不存在或已删除'}, 404);
    }

    final List<Map<String, dynamic>> list =
        comments[id] ?? <Map<String, dynamic>>[];

    if (request.method == 'POST') {
      if (commentPostStatus != null) {
        return _json(
          <String, dynamic>{'detail': commentPostError ?? '评论发表失败'},
          commentPostStatus!,
        );
      }
      // 与服务端一致：没有 Authorization 头就是未登录
      if (request.headers['Authorization'] == null) {
        return _json(<String, dynamic>{'detail': '请先登录'}, 401);
      }

      final Map<String, dynamic> body =
          jsonDecode(utf8.decode(request.bodyBytes)) as Map<String, dynamic>;
      final Map<String, dynamic> created = <String, dynamic>{
        'id': list.length + 1,
        'content': '${body['content']}'.trim(),
        'author': <String, dynamic>{'id': 4, 'name': currentUserName},
        'created_at': '2026-09-30T12:30:00',
      };
      comments[id] = <Map<String, dynamic>>[...list, created];
      return _json(created, 201);
    }

    if (commentReadStatus != null) {
      return _json(
        <String, dynamic>{'detail': commentReadError ?? '评论加载失败'},
        commentReadStatus!,
      );
    }

    final int page = int.tryParse(request.url.queryParameters['page'] ?? '1') ?? 1;
    final int size =
        int.tryParse(request.url.queryParameters['page_size'] ?? '20') ?? 20;
    final int start = (page - 1) * size;
    final List<Map<String, dynamic>> slice = start >= list.length
        ? const <Map<String, dynamic>>[]
        : list.sublist(start, (start + size).clamp(0, list.length));

    return _json(<String, dynamic>{
      'total': list.length,
      'page': page,
      'page_size': size,
      'items': slice,
    }, 200);
  }

  Map<String, dynamic> _userJson(String username) => <String, dynamic>{
        'id': _idFor(username),
        'username': username,
        'nickname': nicknames[username],
        'avatar_url': null,
        'study_days': 0,
      };

  Future<http.Response> _handle(http.Request request) async {
    requests.add(request.url);
    authHeaders.add(request.headers['Authorization']);

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

    // 认证接口与知识接口的失败语义不同，单独走一条分支
    if (path.startsWith('/api/auth/')) {
      return _handleAuth(request, path);
    }

    if (path == '/api/favorites' || path.startsWith('/api/favorites/')) {
      return _handleFavorites(request, path);
    }

    if (path == '/api/history' || path.startsWith('/api/history/')) {
      return _handleHistory(request, path);
    }

    if (path == '/api/posts' || path.startsWith('/api/posts/')) {
      return _handlePosts(request, path);
    }

    if (path == '/api/settings') {
      return _handleSettings(request);
    }

    if (path == '/api/knowledge') {
      return _json(_filtered(request.url.queryParametersAll), 200);
    }

    // POST /api/knowledge/{id}/view —— 与真实的写接口分开处理，
    // 因为它会改变后续 GET 详情的返回值
    if (path.startsWith('/api/knowledge/') && path.endsWith('/view')) {
      final String rawId =
          path.substring('/api/knowledge/'.length, path.length - '/view'.length);
      final int? id = int.tryParse(rawId);
      if (id == null || !_exists(id)) {
        return _json(<String, dynamic>{'detail': '知识不存在或未发布'}, 404);
      }
      final int count = (viewCounts[id] ?? 0) + 1;
      viewCounts[id] = count;

      // 与真实后端一致：浏览时**顺带**写一条历史，但只有登录用户才有
      // 「谁」可以记。匿名浏览照常计数，不写任何人的历史。
      final String? viewer = _usernameFromHeader(request);
      if (viewer != null) _recordHistory(viewer, id);

      return _json(<String, dynamic>{'view_count': count}, 200);
    }

    if (path.startsWith('/api/knowledge/')) {
      final String rawId = path.substring('/api/knowledge/'.length);
      final int? id = int.tryParse(rawId);
      final String? viewer = _usernameFromHeader(request);
      for (final Map<String, dynamic> item in items) {
        if (item['id'] == id) {
          return _json(<String, dynamic>{
            ...item,
            // 条目自带 content 时以它为准（用例可以借此构造「正文为空」），
            // 否则补一段够长的正文
            'content': item['content'] ?? '正文内容，长度足够用于测试。',
            'source': item['source'],
            'author': item['author'],
            'view_count': viewCounts[id] ?? 0,
            // 收藏状态**按人算**：匿名访问恒为 false
            'is_favorited': viewer != null &&
                (favorites[viewer] ?? const <int>[]).contains(id),
          }, 200);
        }
      }
      return _json(<String, dynamic>{'detail': '知识不存在或未发布'}, 404);
    }

    return _json(<String, dynamic>{'detail': '接口不存在'}, 404);
  }

  bool _exists(int id) => items.any((Map<String, dynamic> item) => item['id'] == id);

  /// 认证相关的响应。
  ///
  /// 这里刻意复述了后端的状态码约定（400 / 401 / 409），
  /// 是为了让客户端**按状态码分支处理**这件事在测试里也被覆盖到 ——
  /// 全部返回 200 的话，客户端把失败当成功也测不出来。
  Future<http.Response> _handleAuth(http.Request request, String path) async {
    if (path == '/api/auth/me') {
      if (meErrorStatus != null) {
        return _json(
          <String, dynamic>{'detail': '请先登录'},
          meErrorStatus!,
        );
      }
      final String? username = _usernameFromHeader(request);
      if (username == null) {
        return _json(<String, dynamic>{'detail': '请先登录'}, 401);
      }
      return _json(_userJson(username), 200);
    }

    if (path == '/api/auth/register') {
      final Map<String, dynamic> body = _body(request);
      final String username = (body['username'] as String? ?? '').trim();
      final String password = body['password'] as String? ?? '';

      if (username.isEmpty || password.isEmpty) {
        return _json(<String, dynamic>{'detail': '用户名和密码都要填'}, 400);
      }
      if (accounts.containsKey(username)) {
        return _json(<String, dynamic>{'detail': '该用户名已被注册'}, 409);
      }
      if (password.length < 8) {
        return _json(<String, dynamic>{'detail': '密码至少 8 位'}, 400);
      }

      seedAccount(
        username,
        password,
        nickname: body['nickname'] as String?,
      );
      return _json(_sessionJson(username), 201);
    }

    if (path == '/api/auth/login') {
      final Map<String, dynamic> body = _body(request);
      final String username = (body['username'] as String? ?? '').trim();
      final String password = body['password'] as String? ?? '';

      // 与后端保持一致：用户名不存在与密码错误返回同一句话
      if (accounts[username] != password) {
        return _json(<String, dynamic>{'detail': '用户名或密码不正确'}, 401);
      }
      return _json(_sessionJson(username), 200);
    }

    return _json(<String, dynamic>{'detail': '接口不存在'}, 404);
  }

  /// 收藏相关的响应。
  ///
  /// 复述了后端的两个关键约定：
  ///   - 未登录一律 401「请先登录」
  ///   - 收藏与取消都是**幂等**的（已收藏时 POST 返回 200 而不是 201，
  ///     取消一条本来就没收藏的也返回 204）
  ///
  /// 假后端如果不照做，页面里依赖幂等性的分支就永远测不到。
  Future<http.Response> _handleFavorites(
    http.Request request,
    String path,
  ) async {
    if (favoriteErrorStatus != null) {
      return _json(
        <String, dynamic>{'detail': favoriteErrorMessage},
        favoriteErrorStatus!,
      );
    }

    final String? username = _usernameFromHeader(request);
    if (username == null) {
      return _json(<String, dynamic>{'detail': '请先登录'}, 401);
    }

    final List<int> ids = favorites.putIfAbsent(username, () => <int>[]);

    if (path == '/api/favorites') {
      if (request.method == 'POST') {
        final int? id = (_body(request)['knowledge_id'] as num?)?.toInt();
        if (id == null || !_exists(id)) {
          return _json(<String, dynamic>{'detail': '知识不存在或未发布'}, 404);
        }
        if (ids.contains(id)) {
          return _json(_favoriteRecordJson(username, id), 200);
        }
        ids.add(id);
        return _json(_favoriteRecordJson(username, id), 201);
      }
      return _json(_favoritePage(username, request.url.queryParameters), 200);
    }

    // DELETE /api/favorites/{knowledge_id}
    final int? id = int.tryParse(path.substring('/api/favorites/'.length));
    if (id != null) ids.remove(id);
    return http.Response('', 204);
  }

  /// 与真实后端一致：POST 只回收藏记录本身，不带嵌套知识
  Map<String, dynamic> _favoriteRecordJson(String username, int knowledgeId) {
    final List<int> ids = favorites[username] ?? const <int>[];
    return <String, dynamic>{
      'id': ids.indexOf(knowledgeId) + 1,
      'knowledge_id': knowledgeId,
      'created_at': '2026-09-30T12:00:00',
    };
  }

  /// 列表则**带上嵌套知识**，否则客户端每行都得多发一次详情请求。
  /// 同时只返回仍然存在的条目 —— 与后端的 INNER JOIN 过滤对应。
  Map<String, dynamic> _favoritePage(
    String username,
    Map<String, String> query,
  ) {
    // 最新的排在前面
    final List<int> visible = (favorites[username] ?? const <int>[])
        .reversed
        .where(_exists)
        .toList(growable: false);

    final int page = int.tryParse(query['page'] ?? '1') ?? 1;
    final int pageSize = int.tryParse(query['page_size'] ?? '20') ?? 20;
    final int start = (page - 1) * pageSize;
    final List<int> slice = start >= visible.length
        ? const <int>[]
        : visible.sublist(start, (start + pageSize).clamp(0, visible.length));

    return <String, dynamic>{
      'total': visible.length,
      'page': page,
      'page_size': pageSize,
      'items': <Map<String, dynamic>>[
        for (final int id in slice)
          <String, dynamic>{
            ..._favoriteRecordJson(username, id),
            'knowledge': items.firstWhere(
              (Map<String, dynamic> item) => item['id'] == id,
            ),
          },
      ],
    };
  }

  /// 浏览历史相关的响应。
  ///
  /// 复述了后端的三个关键约定：
  ///   - 未登录一律 401「请先登录」
  ///   - 两个删除接口都是**幂等**的（删一条本来就没有的也是 204）
  ///   - `viewed_at` 是 **naive UTC**（不带 Z）
  ///
  /// 最后一条特别要紧：客户端要自己补时区（见 `core/relative_time.dart`）。
  /// 假后端如果图省事直接吐一个带 Z 的时间，那一步换算就永远测不到了。
  Future<http.Response> _handleHistory(
    http.Request request,
    String path,
  ) async {
    if (historyErrorStatus != null) {
      return _json(
        <String, dynamic>{'detail': historyErrorMessage},
        historyErrorStatus!,
      );
    }

    final String? username = _usernameFromHeader(request);
    if (username == null) {
      return _json(<String, dynamic>{'detail': '请先登录'}, 401);
    }

    final List<int> ids = histories.putIfAbsent(username, () => <int>[]);

    if (path == '/api/history') {
      if (request.method == 'DELETE') {
        ids.clear();
        return http.Response('', 204);
      }
      return _json(_historyPage(username, request.url.queryParameters), 200);
    }

    // DELETE /api/history/{knowledge_id}
    final int? id = int.tryParse(path.substring('/api/history/'.length));
    if (id != null) {
      ids.remove(id);
      _historyAges.remove('$username/$id');
    }
    return http.Response('', 204);
  }

  Map<String, dynamic> _historyRecordJson(String username, int knowledgeId) {
    final Duration age = _historyAges['$username/$knowledgeId'] ?? Duration.zero;
    final DateTime at = DateTime.now().toUtc().subtract(age);

    return <String, dynamic>{
      'id': (histories[username] ?? const <int>[]).indexOf(knowledgeId) + 1,
      'knowledge_id': knowledgeId,
      // 去掉尾部 Z，还原成后端那种 naive UTC
      'viewed_at': at.toIso8601String().replaceFirst('Z', ''),
    };
  }

  /// 列表带上嵌套知识，且只返回仍然存在的条目 ——
  /// 与后端的 INNER JOIN 过滤对应。
  Map<String, dynamic> _historyPage(String username, Map<String, String> query) {
    // 最近看的排在前面
    final List<int> visible = (histories[username] ?? const <int>[])
        .reversed
        .where(_exists)
        .toList(growable: false);

    final int page = int.tryParse(query['page'] ?? '1') ?? 1;
    final int pageSize = int.tryParse(query['page_size'] ?? '20') ?? 20;
    final int start = (page - 1) * pageSize;
    final List<int> slice = start >= visible.length
        ? const <int>[]
        : visible.sublist(start, (start + pageSize).clamp(0, visible.length));

    return <String, dynamic>{
      'total': visible.length,
      'page': page,
      'page_size': pageSize,
      'items': <Map<String, dynamic>>[
        for (final int id in slice)
          <String, dynamic>{
            ..._historyRecordJson(username, id),
            'knowledge': items.firstWhere(
              (Map<String, dynamic> item) => item['id'] == id,
            ),
          },
      ],
    };
  }

  // --- 个性化设置（/api/settings）------------------------------------------

  /// 用户名 -> 设置。**只有写过设置的用户才有键** ——
  /// 与真实后端一致：没写过的用户在 `user_settings` 里没有行，
  /// 读出来的是代码里的默认值。这一点必须在假后端里也成立，
  /// 否则「第一次打开设置页」这条路径永远测不到。
  final Map<String, Map<String, dynamic>> settings =
      <String, Map<String, dynamic>>{};

  /// 没写过设置的用户看到的默认值
  Map<String, dynamic> get defaultSettings => <String, dynamic>{
        'followed_categories': <int>[],
        'home_modules': HomeModule.all
            .map((HomeModule module) => module.id)
            .toList(growable: false),
        'notify_enabled': true,
      };

  /// 预置一份设置（测试里直接构造「已经设置过」的状态）
  void seedSettings(
    String username, {
    List<int> followedCategories = const <int>[],
    List<String>? homeModules,
    bool notifyEnabled = true,
  }) {
    settings[username] = <String, dynamic>{
      'followed_categories': List<int>.from(followedCategories),
      // 显式传 `[]` 与不传**不是一回事**：前者是「全藏起来」，
      // 后者是「还没设置过」。用 `??` 而非 `??=` 就是为了保住这个区别。
      'home_modules': homeModules == null
          ? defaultSettings['home_modules']
          : List<String>.from(homeModules),
      'notify_enabled': notifyEnabled,
    };
  }

  /// 强制设置接口走错误分支（读和写都会中招）
  int? settingsErrorStatus;
  String settingsError = '设置保存失败，请稍后再试';

  /// 依次收到的 PUT 请求体。
  ///
  /// 这是本节最值得盯的地方：分区更新的语义要求「没改的字段
  /// **根本不出现在请求体里**」，而这件事在页面渲染上看不出来 ——
  /// 顺手把三个字段都塞进去，界面照样是对的，只是每保存一次
  /// 都会把另外两项覆盖一遍。
  final List<Map<String, dynamic>> settingsUpdateRequests =
      <Map<String, dynamic>>[];

  /// 复述了后端的四个约定：
  ///   - 未登录一律 401「请先登录」
  ///   - 没写过的用户返回默认值，**不是 404**
  ///   - PUT 只改请求体里出现的字段（显式传 `null` 与不传等价）
  ///   - 分类不存在 404、模块键不认识 422，且**整条请求都不生效**
  Future<http.Response> _handleSettings(http.Request request) async {
    if (settingsErrorStatus != null) {
      return _json(<String, dynamic>{'detail': settingsError}, settingsErrorStatus!);
    }

    final String? username = _usernameFromHeader(request);
    if (username == null) {
      return _json(<String, dynamic>{'detail': '请先登录'}, 401);
    }

    if (request.method == 'PUT') {
      final Map<String, dynamic> body = _body(request);
      settingsUpdateRequests.add(body);

      final Map<String, dynamic> next = <String, dynamic>{
        ...settings[username] ?? defaultSettings,
      };

      final Object? categories = body['followed_categories'];
      if (categories is List) {
        final List<int> ids = categories
            .whereType<num>()
            .map((num value) => value.toInt())
            .toList();
        final Set<int> known =
            kCategories.map((SafetyCategory c) => c.id).toSet();
        final List<int> missing = <int>[
          for (final int id in ids)
            if (!known.contains(id)) id,
        ];
        if (missing.isNotEmpty) {
          return _json(<String, dynamic>{
            'detail': '分类不存在：${missing.join('、')}',
          }, 404);
        }
        next['followed_categories'] = ids.toSet().toList()..sort();
      }

      final Object? modules = body['home_modules'];
      if (modules is List) {
        final List<String> keys = modules.whereType<String>().toList();
        final List<String> unknown = <String>[
          for (final String key in keys)
            if (HomeModule.all.every((HomeModule m) => m.id != key)) key,
        ];
        if (unknown.isNotEmpty) {
          return _json(<String, dynamic>{
            'detail': '首页模块不存在：${unknown.join('、')}',
          }, 422);
        }
        // 按首页顺序排列 —— 与后端 normalize_modules 一致
        next['home_modules'] = <String>[
          for (final HomeModule module in HomeModule.all)
            if (keys.contains(module.id)) module.id,
        ];
      }

      final Object? notify = body['notify_enabled'];
      if (notify is bool) next['notify_enabled'] = notify;

      settings[username] = next;
    }

    return _json(settings[username] ?? defaultSettings, 200);
  }

  Map<String, dynamic> _sessionJson(String username) => <String, dynamic>{
        'access_token': _tokenFor(username),
        'token_type': 'bearer',
        'expires_in': 604800,
        'user': _userJson(username),
      };

  /// 从 Authorization 头里还原出用户名。
  ///
  /// 假 token 就是把用户名拼在前缀后面，因此这里能反解出来 ——
  /// 这样「带着 A 的 token 访问，拿到的是 A 的资料」在测试里也成立。
  String? _usernameFromHeader(http.Request request) {
    final String? header = request.headers['Authorization'];
    if (header == null || !header.startsWith('Bearer ')) return null;
    final String token = header.substring('Bearer '.length);
    if (!token.startsWith(_tokenPrefix)) return null;
    final String username = token.substring(_tokenPrefix.length);
    return accounts.containsKey(username) ? username : null;
  }

  Map<String, dynamic> _body(http.Request request) {
    if (request.bodyBytes.isEmpty) return <String, dynamic>{};
    return jsonDecode(utf8.decode(request.bodyBytes)) as Map<String, dynamic>;
  }

  /// 模拟服务端筛选，返回统一分页结构。
  ///
  /// 收的是 `queryParametersAll` 而不是 `queryParameters`：
  /// 后者遇到重复的同名参数只留下最后一个，`prefer_categories`
  /// 这种可以传多次的参数会被悄悄吞掉。
  Map<String, dynamic> _filtered(Map<String, List<String>> query) {
    String? one(String key) => query[key]?.first;

    Iterable<Map<String, dynamic>> result = items;

    final String? categoryId = one('category_id');
    if (categoryId != null) {
      result = result.where((item) => '${item['category_id']}' == categoryId);
    }

    final String? riskLevel = one('risk_level');
    if (riskLevel != null) {
      result = result.where((item) => item['risk_level'] == riskLevel);
    }

    final String? keyword = one('keyword');
    if (keyword != null) {
      result = result.where((item) =>
          '${item['title']}'.contains(keyword) ||
          '${item['summary']}'.contains(keyword));
    }

    final List<int> preferred = <int>[
      for (final String raw in query['prefer_categories'] ?? const <String>[])
        if (int.tryParse(raw) != null) int.parse(raw),
    ];

    final List<Map<String, dynamic>> list = result.toList();

    // 关注分类优先，与后端 `knowledge_service._preference_rank` 同一套规则：
    // 分两组，组内保持原有先后。不这么做的话，「首页推荐知识把关注方向
    // 排在前面」这件事在 widget 测试里根本验不了。
    if (preferred.isNotEmpty) {
      final List<MapEntry<int, Map<String, dynamic>>> indexed =
          list.asMap().entries.toList()
            ..sort((a, b) {
              int rank(Map<String, dynamic> item) =>
                  preferred.contains(item['category_id']) ? 0 : 1;
              // 用下标兜底：`List.sort` 不保证稳定，
              // 不写这一句的话同组内的先后会随机变。
              return rank(a.value) != rank(b.value)
                  ? rank(a.value) - rank(b.value)
                  : a.key - b.key;
            });
      list
        ..clear()
        ..addAll(indexed.map((entry) => entry.value));
    }

    return <String, dynamic>{
      'total': list.length,
      'page': int.tryParse(one('page') ?? '1') ?? 1,
      'page_size': int.tryParse(one('page_size') ?? '20') ?? 20,
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
