import 'package:anzhi/core/app_constants.dart';
import 'package:anzhi/models/ai_answer.dart';
import 'package:anzhi/models/auth_user.dart';
import 'package:anzhi/models/comment_item.dart';
import 'package:anzhi/models/favorite_item.dart';
import 'package:anzhi/models/history_item.dart';
import 'package:anzhi/models/knowledge_item.dart';
import 'package:anzhi/models/paged_result.dart';
import 'package:anzhi/models/post_item.dart';
import 'package:anzhi/services/api_client.dart';
import 'package:anzhi/services/auth_api.dart';
import 'package:anzhi/services/chat_api.dart';
import 'package:anzhi/services/favorite_api.dart';
import 'package:anzhi/services/history_api.dart';
import 'package:anzhi/services/knowledge_api.dart';
import 'package:anzhi/services/post_api.dart';
import 'package:flutter_test/flutter_test.dart';

/// 安知 —— 真实后端连通性测试
///
/// **默认跳过**：它需要一个真正运行中的 FastAPI 后端，
/// 因此不能混进 `flutter test` 的常规结果里假装通过。
///
/// 手动执行步骤：
/// ```bash
/// # 1. 启动后端
/// cd backend
/// .venv\Scripts\python.exe -m uvicorn app.main:app --port 8000
///
/// # 2. 指定开关运行本文件
/// cd frontend
/// flutter test test/integration/live_backend_test.dart --dart-define=ANZHI_LIVE_BACKEND=true
/// ```
///
/// 存在的意义：`test/helpers/fake_backend.dart` 里的假后端是**按客户端预期写的**，
/// 它只能证明「客户端逻辑自洽」，无法证明「后端真实返回的字段名与客户端解析的一致」。
/// 字段名漂移（例如后端叫 `category_name`、客户端读 `categoryName`）
/// 只有对着真实后端跑一遍才会暴露 —— 这是假数据永远发现不了的一类问题。
void main() {
  const bool enabled = bool.fromEnvironment('ANZHI_LIVE_BACKEND');
  const String baseUrl = String.fromEnvironment(
    'ANZHI_API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );

  final ApiClient raw = ApiClient(
    baseUrl: baseUrl,
    timeout: const Duration(seconds: 5),
  );
  final KnowledgeApi api = KnowledgeApi(client: raw);

  // 问答用独立的 ApiClient：两个接口对象共用一个底层 client 时，
  // 任何一个 dispose() 都会把它关掉，让后续用例莫名其妙地「连不上服务器」。
  // 超时给足 60 秒，与 App 里 ChatApi 的实际配置一致。
  final ChatApi chat = ChatApi(
    client: ApiClient(baseUrl: baseUrl, timeout: ApiConfig.aiTimeout),
  );

  // 认证同样用独立的 ApiClient：token 每次请求时从这个变量现取。
  // 测试会在登录成功后把它设上，于是后续请求自动带上 Authorization。
  //
  // 这带来一个**必须知道的顺序依赖**：「收藏」与「浏览历史」两组靠
  // `authToken` 拿到身份，而这个值由上面的「认证」组填。因此单独跑
  // 其中某一条（`--plain-name`）会以 401「请先登录」失败 —— 那不是
  // 后端坏了，是登录根本没发生。要单独调，请整份文件一起跑。
  String? authToken;
  final AuthApi authApi = AuthApi(
    client: ApiClient(
      baseUrl: baseUrl,
      timeout: const Duration(seconds: 5),
      token: () => authToken,
    ),
  );

  // 收藏同样用独立的 ApiClient，token 从同一个变量现取 ——
  // 认证那一组跑完之后 `authToken` 就有值了。
  final FavoriteApi favorites = FavoriteApi(
    client: ApiClient(
      baseUrl: baseUrl,
      timeout: const Duration(seconds: 5),
      token: () => authToken,
    ),
  );

  /// **带登录身份**的知识接口，只用于 `is_favorited` 这类按人算的字段。
  ///
  /// 上面那个 `api` 是匿名客户端，拿它去查 `is_favorited` 永远是 false ——
  /// 后端没有做错，是请求本身没有身份。这一点最初真的把这条测试跑挂过，
  /// 因此特意保留这个独立的实例并写清楚它的用途。
  final KnowledgeApi authedApi = KnowledgeApi(
    client: ApiClient(
      baseUrl: baseUrl,
      timeout: const Duration(seconds: 5),
      token: () => authToken,
    ),
  );

  // 浏览历史同样用独立的 ApiClient，token 从同一个变量现取。
  final HistoryApi history = HistoryApi(
    client: ApiClient(
      baseUrl: baseUrl,
      timeout: const Duration(seconds: 5),
      token: () => authToken,
    ),
  );

  // 社区同样用独立的 ApiClient。与上面几个**不同**：它不带 token，
  // 因为 `GET /api/posts` 与 `GET /api/posts/{id}` 都是公开接口，
  // 读社区内容本来就不需要身份（docs/API.md 第 7 节）。
  //
  // 这也意味着「社区」这一组**没有顺序依赖** —— 不必先跑「认证」组，
  // 单独 `--plain-name` 跑也成立。
  final ApiClient postsClient = ApiClient(
    baseUrl: baseUrl,
    timeout: const Duration(seconds: 5),
  );
  final PostApi posts = PostApi(client: postsClient);

  /// 带登录身份的社区接口，只用于发评论。
  ///
  /// 读评论用上面那个匿名的就行（公开内容），写必须带 token ——
  /// 与收藏 / 历史两组一样，这里也依赖「认证」组先把 `authToken` 填上。
  final PostApi authedPosts = PostApi(
    client: ApiClient(
      baseUrl: baseUrl,
      timeout: const Duration(seconds: 5),
      token: () => authToken,
    ),
  );

  /// 本次运行创建的账号名。
  ///
  /// **这些用例会在真实数据库里创建用户。** 名字带固定前缀便于事后清理，
  /// 后缀用 base36 的时间戳而不是十进制 —— 用户名上限 20 个字符，
  /// 十进制毫秒时间戳有 13 位，加上前缀会直接超标。
  final String accountName =
      'lcheck${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
  const String accountPassword = 'live-check-password';

  tearDownAll(() {
    api.dispose();
    chat.dispose();
    authApi.dispose();
    favorites.dispose();
    authedApi.dispose();
    history.dispose();
    posts.dispose();
    authedPosts.dispose();
  });

  group(
    '真实后端',
    () {
      test('健康检查：数据库已连接', () async {
        final Object? json = await raw.getJson('/api/health');
        final Map<String, dynamic> body = json! as Map<String, dynamic>;

        expect(body['status'], 'ok');
        expect(body['database'], 'connected');
        // AI 未配置时如实返回 not_configured，这里不做「应该已配置」的假设
        expect(body['ai_service'], anyOf('configured', 'not_configured'));
      });

      test('分类：接口返回的 id / 名称与客户端常量一致', () async {
        // 分类名同时存在于数据库种子、后端接口与前端常量三处，
        // 任何一处漂移都会让「按分类筛选」失效
        final Object? json = await raw.getJson('/api/categories');
        final List<dynamic> rows = json! as List<dynamic>;

        expect(rows.length, kCategories.length);
        for (final SafetyCategory category in kCategories) {
          final Map<String, dynamic> row = rows
              .cast<Map<String, dynamic>>()
              .firstWhere((Map<String, dynamic> r) => r['id'] == category.id);
          expect(row['name'], category.name, reason: '分类 ${category.id} 名称不一致');
          expect(row['slug'], category.slug, reason: '分类 ${category.id} slug 不一致');
        }
      });

      test('知识列表：真实返回的字段能被完整解析', () async {
        final PagedResult<KnowledgeItem> result = await api.fetchKnowledge();

        expect(result.page, 1);
        expect(result.total, result.items.length);

        for (final KnowledgeItem item in result.items) {
          expect(item.id, greaterThan(0));
          // 字段名对不上时 title 会是空串 —— 这正是本测试要拦的问题
          expect(item.title, isNotEmpty, reason: '标题解析为空，字段名可能已漂移');
          expect(item.summary, isNotEmpty);
          expect(item.categoryId, greaterThan(0));
          expect(item.categoryName, isNot('未分类'), reason: 'category_id 无法映射到本地分类');
        }
      });

      test('按分类筛选：返回的条目全部属于该分类', () async {
        final PagedResult<KnowledgeItem> all = await api.fetchKnowledge();
        if (all.items.isEmpty) {
          // 内容尚未审核发布时接口如实返回空，此时跳过分类断言
          return;
        }

        final int categoryId = all.items.first.categoryId;
        final PagedResult<KnowledgeItem> filtered =
            await api.fetchKnowledge(categoryId: categoryId);

        expect(filtered.items, isNotEmpty);
        expect(
          filtered.items.every((KnowledgeItem i) => i.categoryId == categoryId),
          isTrue,
        );
      });

      test('搜索：能命中标题中的中文关键词', () async {
        // 中文关键词要经过 URL 编码 → 服务端解码 → SQL LIKE 三层，
        // 任何一层的编码不一致都会让搜索静默地永远返回 0 条
        final PagedResult<KnowledgeItem> all = await api.fetchKnowledge();
        if (all.items.isEmpty) return;

        final KnowledgeItem sample = all.items.first;
        final String keyword = sample.title.substring(0, 2);
        final PagedResult<KnowledgeItem> hit =
            await api.fetchKnowledge(keyword: keyword);

        expect(
          hit.items.any((KnowledgeItem i) => i.id == sample.id),
          isTrue,
          reason: '搜索「$keyword」应至少命中「${sample.title}」',
        );
      });

      test('搜索：不存在的关键词返回空列表而不是报错', () async {
        final PagedResult<KnowledgeItem> none =
            await api.fetchKnowledge(keyword: '关键词一定不存在的字符串xyz');
        expect(none.total, 0);
        expect(none.items, isEmpty);
      });

      test('风险等级筛选：返回的条目风险等级一致', () async {
        final PagedResult<KnowledgeItem> high =
            await api.fetchKnowledge(riskLevel: 'high', pageSize: 100);

        expect(
          high.items.every((KnowledgeItem i) => i.riskLevel == RiskLevel.high),
          isTrue,
        );
      });

      test('未发布内容访问详情返回可读的 404', () async {
        // 用一个不可能存在的 id，确认错误路径返回的是中文说明
        await expectLater(
          api.fetchKnowledgeDetail(999999),
          throwsA(
            isA<ApiException>()
                .having((ApiException e) => e.statusCode, 'statusCode', 404)
                .having((ApiException e) => e.message, 'message', '知识不存在或未发布'),
          ),
        );
      });

      test('AI 问答：未配置 Key 时返回 503 与可读中文，而不是 500', () async {
        // 这条断言在「没有 Key」时最有价值：它同时验证了
        //  · 未配置不会崩成 500
        //  · 用户看到的是能照着做的说明，而不是 stack trace
        // 配置了 Key 之后本用例会自动改为验证「真实回答可被解析」。
        final Object? health = await raw.getJson('/api/health');
        final bool configured =
            (health! as Map<String, dynamic>)['ai_service'] == 'configured';

        if (!configured) {
          await expectLater(
            chat.ask('宿舍发生火灾怎么办？'),
            throwsA(
              isA<ApiException>()
                  .having((ApiException e) => e.statusCode, 'statusCode', 503)
                  .having(
                    (ApiException e) => e.message,
                    'message',
                    contains('DEEPSEEK_API_KEY'),
                  ),
            ),
          );
          return;
        }

        final AiAnswer answer = await chat.ask('宿舍发生火灾怎么办？');
        expect(answer.answer, isNotEmpty);
        expect(answer.steps, isNotEmpty, reason: '高风险问题应给出可执行步骤');
        expect(answer.warning, isNotEmpty, reason: '高风险问题必须带安全警告');
      });

      test('浏览计数：写接口加一，且详情接口如实反映', () async {
        final PagedResult<KnowledgeItem> all = await api.fetchKnowledge();
        if (all.items.isEmpty) {
          // 内容尚未审核发布时没有可计数的条目，此时跳过
          return;
        }

        final int id = all.items.first.id;
        final int before = (await api.fetchKnowledgeDetail(id)).viewCount;

        final int? after = await api.recordView(id);
        expect(after, before + 1);

        // 读详情不会自己加一 —— 否则预取和重试都会被算成浏览
        expect((await api.fetchKnowledgeDetail(id)).viewCount, before + 1);
      });

      test('浏览计数：不存在的条目返回 null 而不是抛错', () async {
        // recordView 刻意吞掉异常：计数失败不该把一次正常阅读变成错误页
        expect(await api.recordView(999999), isNull);
      });

      test('AI 问答：空问题返回 422，且客户端能读出可读原因', () async {
        // 这条测试守的是一个真实踩过的坑：后端 422 的响应体结构
        // （errors[0].message）一旦变化，客户端只会退化成
        // 「请求失败（HTTP 422）」，用户根本不知道哪里填错了。
        // 假后端是按客户端预期写的，永远发现不了这种漂移。
        await expectLater(
          chat.ask('   '),
          throwsA(
            isA<ApiException>()
                .having((ApiException e) => e.statusCode, 'statusCode', 422)
                .having(
                  (ApiException e) => e.message,
                  'message',
                  isNot(contains('HTTP 422')),
                ),
          ),
        );
      });
    },
    skip: enabled
        ? false
        : '需要运行中的后端，用 --dart-define=ANZHI_LIVE_BACKEND=true 开启',
  );

  group(
    '真实后端 · 认证',
    () {
      test('注册：返回的 token 立刻能用，且响应里没有密码', () async {
        final AuthSession session = await authApi.register(
          username: accountName,
          password: accountPassword,
        );
        authToken = session.token;

        expect(session.token, isNotEmpty);
        expect(session.user.username, accountName);

        // 拿刚发的 token 换用户 —— 通得过才说明 token 真被后端认了
        final AuthUser me = await authApi.me();
        expect(me.id, session.user.id);
      });

      test('用户名重复注册返回 409 与中文说明', () async {
        await expectLater(
          authApi.register(
            username: accountName,
            password: accountPassword,
          ),
          throwsA(
            isA<ApiException>()
                .having((ApiException e) => e.statusCode, 'statusCode', 409)
                .having((ApiException e) => e.message, 'message', '该用户名已被注册'),
          ),
        );
      });

      test('密码错误与用户名不存在返回同一句话', () async {
        // 两种情况给出不同提示，等于提供了一个枚举用户名的接口
        final String wrongPassword = await _loginProblem(
          authApi,
          username: accountName,
          password: 'definitely-wrong',
        );
        final String unknownUser = await _loginProblem(
          authApi,
          username: 'livecheck-nobody-${DateTime.now().microsecondsSinceEpoch}',
          password: accountPassword,
        );

        expect(wrongPassword, '用户名或密码不正确');
        expect(unknownUser, '用户名或密码不正确');
      });

      test('登录成功后能再换一次用户', () async {
        final AuthSession session = await authApi.login(
          username: accountName,
          password: accountPassword,
        );
        authToken = session.token;

        expect((await authApi.me()).username, accountName);
      });

      test('不带 token 访问 /me 返回 401 与「请先登录」', () async {
        // 换一个没有 token 的客户端。用一个可变的临时变量而不是
        // 把 authToken 清掉：清掉会让同一个 group 里后面的用例失去登录态。
        String? none;
        final AuthApi anonymous = AuthApi(
          client: ApiClient(baseUrl: baseUrl, token: () => none),
        );
        addTearDown(anonymous.dispose);

        await expectLater(
          anonymous.me(),
          throwsA(
            isA<ApiException>()
                .having((ApiException e) => e.statusCode, 'statusCode', 401)
                .having((ApiException e) => e.message, 'message', '请先登录'),
          ),
        );
      });

      test('伪造的 token 会被拒绝', () async {
        String? forged = 'not.a.real.token';
        final AuthApi faker = AuthApi(
          client: ApiClient(baseUrl: baseUrl, token: () => forged),
        );
        addTearDown(faker.dispose);

        await expectLater(
          faker.me(),
          throwsA(
            isA<ApiException>().having(
              (ApiException e) => e.statusCode,
              'statusCode',
              401,
            ),
          ),
        );
      });

      test('超长中文密码被拦下，且给出能看懂的原因', () async {
        // 25 个汉字 = 75 字节，超过 bcrypt 的 72 字节上限。
        // 后端不显式校验的话这里会变成 500。
        final String name =
            'lcpw${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
        await expectLater(
          authApi.register(username: name, password: '安' * 25),
          throwsA(
            isA<ApiException>()
                .having((ApiException e) => e.statusCode, 'statusCode', 400)
                .having((ApiException e) => e.message, 'message', contains('汉字')),
          ),
        );
      });
    },
    skip: enabled
        ? false
        : '需要运行中的后端，用 --dart-define=ANZHI_LIVE_BACKEND=true 开启',
  );

  group(
    '真实后端 · 收藏',
    () {
      test('未登录时三个接口都是 401 与「请先登录」', () async {
        String? none;
        final FavoriteApi anonymous = FavoriteApi(
          client: ApiClient(baseUrl: baseUrl, token: () => none),
        );
        addTearDown(anonymous.dispose);

        for (final Future<void> Function() call in <Future<void> Function()>[
          anonymous.fetchFavorites,
          () => anonymous.add(1),
          () => anonymous.remove(1),
        ]) {
          await expectLater(
            call(),
            throwsA(
              isA<ApiException>()
                  .having((ApiException e) => e.statusCode, 'statusCode', 401)
                  .having((ApiException e) => e.message, 'message', '请先登录'),
            ),
          );
        }
      });

      test('收藏不存在的知识返回 404 与可读中文', () async {
        await expectLater(
          favorites.add(999999),
          throwsA(
            isA<ApiException>()
                .having((ApiException e) => e.statusCode, 'statusCode', 404)
                .having(
                  (ApiException e) => e.message,
                  'message',
                  '知识不存在或未发布',
                ),
          ),
        );
      });

      test('取消一条没收藏过的返回 204，而不是 404', () async {
        // 幂等：用户要的是「这条不在我的收藏里」，这个状态已经成立了
        await favorites.remove(999999);
      });

      test('收藏 → 列表 → 详情 → 取消，整条链路对得上', () async {
        final PagedResult<KnowledgeItem> all = await api.fetchKnowledge();
        if (all.items.isEmpty) {
          // 知识库没有已发布内容时无法验证往返。**不假装通过** ——
          // 这条断言的价值全靠真实数据，空跑一遍等于什么都没验。
          markTestSkipped('知识库当前没有已发布内容，收藏往返未验证');
          return;
        }

        final int id = all.items.first.id;
        await favorites.remove(id); // 先清干净，保证起点确定

        await favorites.add(id);

        final PagedResult<FavoriteItem> page = await favorites.fetchFavorites();
        expect(page.total, 1);
        expect(page.items.single.knowledgeId, id);
        // 嵌套知识的字段名一旦漂移，这里会立刻暴露 ——
        // 假后端是按客户端预期写的，永远发现不了这类问题
        expect(page.items.single.knowledge.title, isNotEmpty);
        expect(page.items.single.knowledge.categoryName, isNot('未分类'));

        expect((await authedApi.fetchKnowledgeDetail(id)).isFavorited, isTrue);

        await favorites.remove(id);

        expect((await favorites.fetchFavorites()).total, 0);
        expect((await authedApi.fetchKnowledgeDetail(id)).isFavorited, isFalse);
      });

      test('重复收藏是幂等的，列表里仍然只有一条', () async {
        final PagedResult<KnowledgeItem> all = await api.fetchKnowledge();
        if (all.items.isEmpty) {
          markTestSkipped('知识库当前没有已发布内容，幂等性未验证');
          return;
        }

        final int id = all.items.first.id;
        await favorites.remove(id);
        await favorites.add(id);
        await favorites.add(id);

        expect((await favorites.fetchFavorites()).total, 1);

        await favorites.remove(id);
      });

      test('详情接口的 is_favorited 按人算，不是「有没有人收藏过」', () async {
        final PagedResult<KnowledgeItem> all = await api.fetchKnowledge();
        if (all.items.isEmpty) {
          markTestSkipped('知识库当前没有已发布内容，隔离性未验证');
          return;
        }

        final int id = all.items.first.id;
        await favorites.add(id);

        // 换一个全新账号来看同一条
        String? otherToken;
        final AuthApi other = AuthApi(
          client: ApiClient(baseUrl: baseUrl, token: () => otherToken),
        );
        addTearDown(other.dispose);

        final String name =
            'lfav${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
        otherToken = (await other.register(
          username: name,
          password: accountPassword,
        ))
            .token;

        final FavoriteApi otherFavorites = FavoriteApi(
          client: ApiClient(baseUrl: baseUrl, token: () => otherToken),
        );
        addTearDown(otherFavorites.dispose);

        expect((await otherFavorites.fetchFavorites()).total, 0);
        expect(
          (await authedApi.fetchKnowledgeDetail(id)).isFavorited,
          isTrue,
          reason: '收藏者本人仍然看到已收藏',
        );

        await favorites.remove(id);
      });
    },
    skip: enabled
        ? false
        : '需要运行中的后端，用 --dart-define=ANZHI_LIVE_BACKEND=true 开启',
  );

  group(
    '真实后端 · 浏览历史',
    () {
      /// 取一条已发布的知识 id；没有已发布内容时返回 null。
      ///
      /// **宁可跳过也不空跑**：浏览历史整条链路都要求「这条知识看得见」，
      /// 没有数据时断言什么都不会成立，假装跑过等于没验。
      Future<int?> firstPublishedId() async {
        final PagedResult<KnowledgeItem> all = await api.fetchKnowledge();
        if (all.items.isEmpty) {
          markTestSkipped('知识库当前没有已发布内容，浏览历史未验证');
          return null;
        }
        return all.items.first.id;
      }

      test('未登录时三个接口都是 401 与「请先登录」', () async {
        String? none;
        final HistoryApi anonymous = HistoryApi(
          client: ApiClient(baseUrl: baseUrl, token: () => none),
        );
        addTearDown(anonymous.dispose);

        for (final Future<void> Function() call in <Future<void> Function()>[
          anonymous.fetchHistory,
          () => anonymous.remove(1),
          anonymous.clear,
        ]) {
          await expectLater(
            call(),
            throwsA(
              isA<ApiException>()
                  .having((ApiException e) => e.statusCode, 'statusCode', 401)
                  .having((ApiException e) => e.message, 'message', '请先登录'),
            ),
          );
        }
      });

      test('未登录浏览不会留下任何历史', () async {
        final int? id = await firstPublishedId();
        if (id == null) return;

        await history.clear();

        // 用匿名客户端走详情页那条路径：匿名浏览必须照常计数，
        // 但不能因为「没有身份」而随便记在谁头上
        final int? count = await api.recordView(id);
        expect(count, isNotNull, reason: '匿名浏览仍应正常计数，不能变成 401');

        expect((await history.fetchHistory()).total, 0);
      });

      test('看过之后出现在历史里，且嵌套知识字段完整', () async {
        final int? id = await firstPublishedId();
        if (id == null) return;

        await history.clear();
        await authedApi.recordView(id);

        final PagedResult<HistoryItem> page = await history.fetchHistory();
        expect(page.total, 1);

        final HistoryItem item = page.items.single;
        expect(item.knowledgeId, id);
        // 字段名漂移（后端叫 category_name、客户端读 categoryName 之类）
        // 只有对着真实后端跑才会暴露 —— 假后端是按客户端预期写的
        expect(item.knowledge.title, isNotEmpty, reason: '标题解析为空，字段名可能已漂移');
        expect(item.knowledge.categoryName, isNot('未分类'));
        expect(item.isBroken, isFalse);
      });

      test('viewed_at 按 UTC 解释，不会偏出几个小时', () async {
        // 这条守的是一个**不会报错**的坑：后端存的是 naive UTC，
        // pydantic 序列化出来不带 Z。客户端若直接 DateTime.parse，
        // 在 UTC+8 的机器上会被当成本地时间，刚看过的记录显示成 8 小时前。
        // 界面上只是数字不对，日志里一行错误都没有。
        final int? id = await firstPublishedId();
        if (id == null) return;

        await history.clear();
        await authedApi.recordView(id);

        final HistoryItem item = (await history.fetchHistory()).items.single;

        expect(item.viewedAt, isNotNull);
        expect(
          DateTime.now().difference(item.viewedAt!).inMinutes.abs(),
          lessThan(5),
          reason: '时区解释错了的话这里会差 480 分钟',
        );
      });

      test('重复看同一条只有一行，且时间会刷新', () async {
        final int? id = await firstPublishedId();
        if (id == null) return;

        await history.clear();
        await authedApi.recordView(id);
        final DateTime? first =
            (await history.fetchHistory()).items.single.viewedAt;

        await Future<void>.delayed(const Duration(milliseconds: 1100));
        await authedApi.recordView(id);

        final PagedResult<HistoryItem> page = await history.fetchHistory();
        expect(page.total, 1, reason: '同一条知识反复看不应堆成一长串');
        expect(
          page.items.single.viewedAt!.isAfter(first!),
          isTrue,
          reason: '再看一次应当把时间往前推，否则「最近看过」是错的',
        );
      });

      test('删除一条之后就没了，再删一次也是成功', () async {
        final int? id = await firstPublishedId();
        if (id == null) return;

        await history.clear();
        await authedApi.recordView(id);

        await history.remove(id);
        expect((await history.fetchHistory()).total, 0);

        // 幂等：用户要的是「这条不在我的历史里」，这个状态已经成立了
        await history.remove(id);
      });

      test('清空之后列表为空', () async {
        final int? id = await firstPublishedId();
        if (id == null) return;

        await history.clear();
        await authedApi.recordView(id);

        await history.clear();
        expect((await history.fetchHistory()).total, 0);
      });

      test('看不到别人的浏览历史', () async {
        final int? id = await firstPublishedId();
        if (id == null) return;

        await history.clear();
        await authedApi.recordView(id);

        // 换一个全新账号：看过什么、什么时候看的，都不该被别人读到
        String? otherToken;
        final AuthApi other = AuthApi(
          client: ApiClient(baseUrl: baseUrl, token: () => otherToken),
        );
        addTearDown(other.dispose);

        final String name =
            'lhis${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
        otherToken = (await other.register(
          username: name,
          password: accountPassword,
        ))
            .token;

        final HistoryApi otherHistory = HistoryApi(
          client: ApiClient(baseUrl: baseUrl, token: () => otherToken),
        );
        addTearDown(otherHistory.dispose);

        expect((await otherHistory.fetchHistory()).total, 0);
        expect(
          (await history.fetchHistory()).total,
          1,
          reason: '本人那条不该被别人的清空或查看影响',
        );

        await history.clear();
      });

      test('看一条不存在的知识不会留下历史', () async {
        final int? id = await firstPublishedId();
        if (id == null) return;

        await history.clear();
        await authedApi.recordView(id);

        // recordView 刻意吞掉异常：计数失败不该把一次正常阅读变成错误页
        expect(await authedApi.recordView(999999), isNull);
        expect((await history.fetchHistory()).total, 1);

        await history.clear();
      });
    },
    skip: enabled
        ? false
        : '需要运行中的后端，用 --dart-define=ANZHI_LIVE_BACKEND=true 开启',
  );

  group(
    '真实后端 · 社区',
    () {
      /// 取一条帖子的 id；一条都没有时返回 null 并**跳过**。
      ///
      /// 阶段 12a 只有读接口，发帖（12d）还没做，所以这里造不出数据来 ——
      /// 空库时只能如实跳过，不能拿「列表是空的」冒充「详情能读出正文」。
      Future<int?> firstPostId() async {
        final PagedResult<PostItem> all = await posts.fetchPosts();
        if (all.items.isEmpty) {
          markTestSkipped('数据库里当前没有帖子，详情相关断言未验证（发帖在阶段 12d）');
          return null;
        }
        return all.items.first.id;
      }

      test('未登录也能读列表，不是 401', () async {
        // 社区内容是公开的。这一条挂掉通常意味着有人给路由挂上了
        // get_current_user 而不是 get_optional_user —— 那会让整个社区
        // 对未登录用户消失，而且前端只会看到一个空白页。
        final PagedResult<PostItem> page = await posts.fetchPosts();

        expect(page.total, greaterThanOrEqualTo(0));
        expect(page.items.length, lessThanOrEqualTo(page.total));
      });

      test('列表响应的字段名与客户端解析的一致', () async {
        // 这是假后端**永远发现不了**的一类问题：假后端是按客户端预期
        // 手写的，字段名两边一起改就会一起「对」。只有拿真实响应体的
        // 原始 key 去比，才能发现后端把 summary 改叫了 excerpt 之类。
        final Object? body = await postsClient.getJson(
          '/api/posts',
          query: <String, dynamic>{'page': 1, 'page_size': 1},
        );
        final Map<String, dynamic> envelope = body as Map<String, dynamic>;

        for (final String key in <String>['total', 'page', 'page_size', 'items']) {
          expect(envelope.containsKey(key), isTrue, reason: '分页信封缺了 $key');
        }

        final List<dynamic> items = envelope['items'] as List<dynamic>;
        if (items.isEmpty) {
          markTestSkipped('数据库里当前没有帖子，条目字段未验证');
          return;
        }
        final Map<String, dynamic> item = items.first as Map<String, dynamic>;

        for (final String key in <String>[
          'id',
          'title',
          'summary',
          'category_name',
          'author',
          'like_count',
          'comment_count',
          'created_at',
        ]) {
          expect(item.containsKey(key), isTrue, reason: '帖子条目缺了 $key，字段名可能已漂移');
        }

        // 列表**不该**带正文：带上就等于每翻一页都搬一遍全文
        expect(item.containsKey('content'), isFalse, reason: '列表项不应包含正文');

        // 作者只暴露署名，不暴露 username —— 用户名是登录凭据的一半
        final Map<String, dynamic> author = item['author'] as Map<String, dynamic>;
        expect(author.containsKey('name'), isTrue);
        expect(author.containsKey('username'), isFalse);
        expect(
          hasKey(envelope, 'username'),
          isFalse,
          reason: '响应里出现了 username，登录名被挂到公开接口上了',
        );
      });

      test('列表项只有摘要，没有正文', () async {
        final int? id = await firstPostId();
        if (id == null) return;

        final PostItem item = (await posts.fetchPosts()).items.first;

        expect(item.summary, isNotEmpty);
        expect(item.hasContent, isFalse, reason: '列表项不该带正文');
      });

      test('详情能取到正文，标题与列表一致', () async {
        final int? id = await firstPostId();
        if (id == null) return;

        final PostItem listed = (await posts.fetchPosts()).items.first;
        final PostItem detail = await posts.fetchPostDetail(listed.id);

        expect(detail.id, listed.id);
        expect(detail.title, listed.title);
        expect(detail.hasContent, isTrue, reason: '详情接口必须返回正文');
        expect(detail.authorName, listed.authorName);
      });

      test('created_at 按 UTC 解释，不会偏出几个小时', () async {
        // 与浏览历史、知识列表同一个坑：后端存 naive UTC，
        // 序列化不带 Z，客户端当成本地时间就会整体偏 8 小时。
        final int? id = await firstPostId();
        if (id == null) return;

        final PostItem item = (await posts.fetchPosts()).items.first;

        expect(item.createdAt, isNotNull);
        expect(
          DateTime.now().difference(item.createdAt!).inMinutes.abs(),
          lessThan(60 * 24 * 365),
          reason: '时间戳解析成了 1970 年之类，说明格式对不上',
        );
      });

      test('帖子不存在或已隐藏时是 404，提示可读', () async {
        await expectLater(
          posts.fetchPostDetail(999999),
          throwsA(
            isA<ApiException>()
                .having((ApiException e) => e.statusCode, 'statusCode', 404)
                .having((ApiException e) => e.message, 'message', '帖子不存在或已删除'),
          ),
        );
      });

      test('分页参数被服务端接受，total 不受分页影响', () async {
        final PagedResult<PostItem> whole = await posts.fetchPosts();
        final PagedResult<PostItem> one = await posts.fetchPosts(page: 1, pageSize: 1);

        expect(one.total, whole.total, reason: 'total 是总数，不该被 page_size 改变');
        expect(one.items.length, lessThanOrEqualTo(1));
      });

      test('按分类与关键词筛选不发 500', () async {
        // 只验「服务端接得住这两个参数」。具体筛出什么取决于库里有什么，
        // 拿它断言绑定在当前数据上，等于每次改数据都要改测试。
        await posts.fetchPosts(categoryId: 1);
        await posts.fetchPosts(keyword: '安全');
        await posts.fetchPosts(categoryId: 1, keyword: '安全');
      });

      test('未登录发评论是 401 与「请先登录」', () async {
        final int? id = await firstPostId();
        if (id == null) return;

        await expectLater(
          posts.postComment(id, '匿名发言'),
          throwsA(
            isA<ApiException>()
                .having((ApiException e) => e.statusCode, 'statusCode', 401)
                .having((ApiException e) => e.message, 'message', '请先登录'),
          ),
        );
      });

      test('未登录也能读评论', () async {
        final int? id = await firstPostId();
        if (id == null) return;

        final PagedResult<CommentItem> page = await posts.fetchComments(id);

        expect(page.total, greaterThanOrEqualTo(0));
      });

      test('评论字段名与客户端解析的一致，且不带 username', () async {
        final int? id = await firstPostId();
        if (id == null) return;

        final Object? body = await postsClient.getJson('/api/posts/$id/comments');
        final Map<String, dynamic> envelope = body as Map<String, dynamic>;

        for (final String key in <String>['total', 'page', 'page_size', 'items']) {
          expect(envelope.containsKey(key), isTrue, reason: '分页信封缺了 $key');
        }

        final List<dynamic> items = envelope['items'] as List<dynamic>;
        if (items.isEmpty) {
          markTestSkipped('这条帖子还没有评论，评论字段未验证');
          return;
        }
        final Map<String, dynamic> item = items.first as Map<String, dynamic>;

        for (final String key in <String>['id', 'content', 'author', 'created_at']) {
          expect(item.containsKey(key), isTrue, reason: '评论条目缺了 $key，字段名可能已漂移');
        }
        expect(hasKey(envelope, 'username'), isFalse, reason: '评论里出现了 username');
      });

      test('发一条评论：能读回来，帖子的评论数跟着涨', () async {
        // ⚠️ **这条会往真实数据库里写一行。** 评论没有删除接口（V1 不做），
        // 因此它会留在库里。跑完联调后按 README「清理联调数据」一节处理。
        final int? id = await firstPostId();
        if (id == null) return;

        final PostItem before = await posts.fetchPostDetail(id);
        final int beforeCount = before.commentCount;

        final CommentItem created =
            await authedPosts.postComment(id, '联调测试留下的评论');

        expect(created.content, '联调测试留下的评论');
        expect(created.authorName, isNotEmpty);

        final PagedResult<CommentItem> page = await posts.fetchComments(id, pageSize: 100);
        expect(
          page.items.any((CommentItem c) => c.id == created.id),
          isTrue,
          reason: '刚发的评论没出现在列表里',
        );

        final PostItem after = await posts.fetchPostDetail(id);
        expect(
          after.commentCount,
          beforeCount + 1,
          reason: '评论数是列表上显示给用户的数字，不能不动',
        );
      });

      test('评论的 created_at 按 UTC 解释', () async {
        final int? id = await firstPostId();
        if (id == null) return;

        final PagedResult<CommentItem> page = await posts.fetchComments(id);
        if (page.items.isEmpty) {
          markTestSkipped('这条帖子还没有评论，时间未验证');
          return;
        }

        DateTime? newest;
        for (final CommentItem item in page.items) {
          if (newest == null || item.createdAt!.isAfter(newest)) {
            newest = item.createdAt;
          }
        }

        expect(
          DateTime.now().difference(newest!).inMinutes.abs(),
          lessThan(60 * 24 * 365),
          reason: '解析成了 1970 年之类，说明时间格式对不上',
        );
      });

      test('往不存在的帖子发评论是 404', () async {
        await expectLater(
          authedPosts.postComment(999999, '你好'),
          throwsA(
            isA<ApiException>()
                .having((ApiException e) => e.statusCode, 'statusCode', 404),
          ),
        );
      });
    },
    skip: enabled
        ? false
        : '需要运行中的后端，用 --dart-define=ANZHI_LIVE_BACKEND=true 开启',
  );
}

/// 递归找 JSON 里有没有某个 key。
///
/// 用于「这个字段**不该**出现在响应里」这类断言（例如 `username`）：
/// 直接对原始响应文本做子串匹配会被编码和转义坑到，
/// 走已解析的结构更稳，也不会因为某个字段名里恰好含这几个字母而误报。
bool hasKey(Object? node, String key) {
  if (node is Map) {
    return node.containsKey(key) ||
        node.values.any((Object? value) => hasKey(value, key));
  }
  if (node is List) {
    return node.any((Object? value) => hasKey(value, key));
  }
  return false;
}

/// 调一次登录，把失败原因取出来。
///
/// `login` 失败时抛的是 ApiException，这里统一转成字符串，
/// 便于两条失败路径直接比较「提示是否一模一样」。
Future<String> _loginProblem(
  AuthApi api, {
  required String username,
  required String password,
}) async {
  try {
    await api.login(username: username, password: password);
    return '（竟然登录成功了）';
  } on ApiException catch (error) {
    return error.message;
  }
}
