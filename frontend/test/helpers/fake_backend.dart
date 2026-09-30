import 'dart:convert';

import 'package:anzhi/core/auth_controller.dart';
import 'package:anzhi/services/api_client.dart';
import 'package:anzhi/services/auth_api.dart';
import 'package:anzhi/services/auth_store.dart';
import 'package:anzhi/services/chat_api.dart';
import 'package:anzhi/services/favorite_api.dart';
import 'package:anzhi/services/history_api.dart';
import 'package:anzhi/services/post_api.dart';
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
  int seedPost({
    required String title,
    String content = '正文。',
    int? categoryId,
    String author = '小艾',
    int likeCount = 0,
    int commentCount = 0,
    String createdAt = '2026-09-30T12:00:00',
  }) {
    final int id = posts.length + 1;
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

  /// 清空帖子目录（测「还没有人发帖」用）
  void seedNoPosts() => posts = <Map<String, dynamic>>[];

  Map<String, dynamic> _postSummaryJson(Map<String, dynamic> post) {
    // 与真实后端一致：列表项**不带 content**，只有 summary
    final Map<String, dynamic> copy = Map<String, dynamic>.from(post)
      ..remove('content');
    return copy;
  }

  Map<String, dynamic> _postPage(Map<String, String> query) {
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
      'items': slice.map(_postSummaryJson).toList(),
    };
  }

  Future<http.Response> _handlePosts(http.Request request, String path) async {
    if (path == '/api/posts') {
      return _json(_postPage(request.url.queryParameters), 200);
    }

    final String rest = path.substring('/api/posts/'.length);
    if (rest.endsWith('/comments')) {
      final int? postId =
          int.tryParse(rest.substring(0, rest.length - '/comments'.length));
      return _handleComments(request, postId);
    }

    final int? id = int.tryParse(rest);
    final Map<String, dynamic>? post = _findPost(id);

    if (post == null) {
      return _json(<String, dynamic>{'detail': '帖子不存在或已删除'}, 404);
    }
    if (request.method == 'DELETE') {
      posts = posts.where((Map<String, dynamic> p) => p['id'] != id).toList();
      return _json(<String, dynamic>{}, 204);
    }
    return _json(post, 200);
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

    if (path == '/api/knowledge') {
      return _json(_filtered(request.url.queryParameters), 200);
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
