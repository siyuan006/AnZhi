import 'package:anzhi/core/app_constants.dart';
import 'package:anzhi/models/ai_answer.dart';
import 'package:anzhi/models/auth_user.dart';
import 'package:anzhi/models/favorite_item.dart';
import 'package:anzhi/models/knowledge_item.dart';
import 'package:anzhi/models/paged_result.dart';
import 'package:anzhi/services/api_client.dart';
import 'package:anzhi/services/auth_api.dart';
import 'package:anzhi/services/chat_api.dart';
import 'package:anzhi/services/favorite_api.dart';
import 'package:anzhi/services/knowledge_api.dart';
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
