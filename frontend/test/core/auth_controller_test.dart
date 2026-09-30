import 'package:anzhi/core/auth_controller.dart';
import 'package:anzhi/models/auth_user.dart';
import 'package:anzhi/services/auth_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_backend.dart';

/// 安知 —— 登录状态测试（阶段 11）
///
/// 这一层最容易出的两类问题：
///  · 登录成功后 token 没有真正带上（界面显示已登录，请求却是匿名的）
///  · 本地 token 已失效，界面却还显示着已登录
void main() {
  group('登录', () {
    test('成功后保存 token 与用户', () async {
      final FakeBackend backend = FakeBackend()..seedAccount('xiaoming', 'hunter2hunter2');
      final MemoryAuthStore store = MemoryAuthStore();
      final AuthController auth = AuthController(
        httpClient: backend.httpClient,
        baseUrl: 'http://test.local',
        store: store,
      );

      final String? problem = await auth.login(
        username: 'xiaoming',
        password: 'hunter2hunter2',
      );

      expect(problem, isNull);
      expect(auth.isLoggedIn, isTrue);
      expect(auth.user!.username, 'xiaoming');
      expect(auth.token, isNotEmpty);
      expect(await store.readToken(), auth.token);
    });

    test('用户名或密码错误时返回可读中文，且不进入登录态', () async {
      final FakeBackend backend = FakeBackend()..seedAccount('xiaoming', 'hunter2hunter2');
      final AuthController auth = AuthController(httpClient: backend.httpClient, baseUrl: 'http://test.local');

      final String? problem = await auth.login(
        username: 'xiaoming',
        password: 'wrong-password',
      );

      expect(problem, '用户名或密码不正确');
      expect(auth.isLoggedIn, isFalse);
      expect(auth.token, isNull);
    });

    test('连不上后端时如实说明，而不是假装登录失败', () async {
      final FakeBackend backend = FakeBackend()..offline = true;
      final AuthController auth = AuthController(httpClient: backend.httpClient, baseUrl: 'http://test.local');

      final String? problem = await auth.login(
        username: 'xiaoming',
        password: 'hunter2hunter2',
      );

      expect(problem, isNotNull);
      expect(problem, contains('无法连接到服务器'));
      expect(auth.isLoggedIn, isFalse);
    });

    test('登录成功会通知监听者', () async {
      final FakeBackend backend = FakeBackend()..seedAccount('xiaoming', 'hunter2hunter2');
      final AuthController auth = AuthController(httpClient: backend.httpClient, baseUrl: 'http://test.local');
      int notifications = 0;
      auth.addListener(() => notifications++);

      await auth.login(username: 'xiaoming', password: 'hunter2hunter2');

      expect(notifications, greaterThan(0));
    });
  });

  group('注册', () {
    test('成功后直接进入登录态，不必再登录一次', () async {
      final FakeBackend backend = FakeBackend();
      final AuthController auth = AuthController(httpClient: backend.httpClient, baseUrl: 'http://test.local');

      final String? problem = await auth.register(
        username: 'newbie',
        password: 'hunter2hunter2',
      );

      expect(problem, isNull);
      expect(auth.isLoggedIn, isTrue);
      expect(auth.user!.username, 'newbie');
    });

    test('用户名重复时如实转达后端说明', () async {
      final FakeBackend backend = FakeBackend()..seedAccount('taken', 'hunter2hunter2');
      final AuthController auth = AuthController(httpClient: backend.httpClient, baseUrl: 'http://test.local');

      final String? problem = await auth.register(
        username: 'taken',
        password: 'hunter2hunter2',
      );

      expect(problem, '该用户名已被注册');
      expect(auth.isLoggedIn, isFalse);
    });

    test('密码过短时如实转达后端说明', () async {
      // 客户端**不自己复述**长度规则：两处各写一份迟早会不一致
      final FakeBackend backend = FakeBackend();
      final AuthController auth = AuthController(httpClient: backend.httpClient, baseUrl: 'http://test.local');

      final String? problem = await auth.register(
        username: 'newbie',
        password: 'abc',
      );

      expect(problem, '密码至少 8 位');
    });

    test('昵称可以留空', () async {
      final FakeBackend backend = FakeBackend();
      final AuthController auth = AuthController(httpClient: backend.httpClient, baseUrl: 'http://test.local');

      await auth.register(username: 'newbie', password: 'hunter2hunter2');

      expect(auth.user!.displayName, 'newbie');
    });

    test('昵称会被显示优先使用', () async {
      final FakeBackend backend = FakeBackend();
      final AuthController auth = AuthController(httpClient: backend.httpClient, baseUrl: 'http://test.local');

      await auth.register(
        username: 'newbie',
        password: 'hunter2hunter2',
        nickname: '小明',
      );

      expect(auth.user!.displayName, '小明');
    });
  });

  group('启动时恢复登录态', () {
    test('本地没有 token 时安静地保持未登录', () async {
      final FakeBackend backend = FakeBackend();
      final AuthController auth = AuthController(
        httpClient: backend.httpClient, baseUrl: 'http://test.local',
        store: MemoryAuthStore(),
      );

      await auth.restore();

      expect(auth.isLoggedIn, isFalse);
      expect(auth.restoring, isFalse);
    });

    test('本地 token 有效时恢复出用户', () async {
      final FakeBackend backend = FakeBackend()..seedAccount('xiaoming', 'hunter2hunter2');
      final MemoryAuthStore store = MemoryAuthStore();
      await store.writeToken('fake-token-for-xiaoming');

      final AuthController auth = AuthController(
        httpClient: backend.httpClient,
        baseUrl: 'http://test.local',
        store: store,
      );
      await auth.restore();

      expect(auth.isLoggedIn, isTrue);
      expect(auth.user!.username, 'xiaoming');
    });

    test('token 已失效时回到未登录，且把坏 token 清掉', () async {
      // 这是最容易被做假的一处：界面显示着登录态，
      // 实际每个请求都因为 token 无效而失败
      final FakeBackend backend = FakeBackend()
        ..seedAccount('xiaoming', 'hunter2hunter2')
        ..meErrorStatus = 401;
      final MemoryAuthStore store = MemoryAuthStore();
      await store.writeToken('fake-token-for-xiaoming');

      final AuthController auth = AuthController(
        httpClient: backend.httpClient, baseUrl: 'http://test.local',
        store: store,
      );
      await auth.restore();

      expect(auth.isLoggedIn, isFalse);
      expect(auth.token, isNull);
      expect(await store.readToken(), isNull, reason: '失效的 token 不该留在本地');
    });

    test('恢复期间 restoring 为 true，结束后为 false', () async {
      final FakeBackend backend = FakeBackend()..delay = const Duration(milliseconds: 30);
      final MemoryAuthStore store = MemoryAuthStore();
      await store.writeToken('fake-token-for-xiaoming');
      backend.seedAccount('xiaoming', 'hunter2hunter2');

      final AuthController auth = AuthController(
        httpClient: backend.httpClient, baseUrl: 'http://test.local',
        store: store,
      );
      final Future<void> restoring = auth.restore();

      expect(auth.restoring, isTrue, reason: '界面要据此避免闪一下「未登录」');
      await restoring;
      expect(auth.restoring, isFalse);
    });
  });

  group('登出', () {
    test('清掉 token 与用户', () async {
      final FakeBackend backend = FakeBackend()..seedAccount('xiaoming', 'hunter2hunter2');
      final MemoryAuthStore store = MemoryAuthStore();
      final AuthController auth = AuthController(
        httpClient: backend.httpClient,
        baseUrl: 'http://test.local',
        store: store,
      );
      await auth.login(username: 'xiaoming', password: 'hunter2hunter2');

      await auth.logout();

      expect(auth.isLoggedIn, isFalse);
      expect(auth.token, isNull);
      expect(await store.readToken(), isNull);
    });

    test('未登录时登出不报错', () async {
      final FakeBackend backend = FakeBackend();
      final AuthController auth = AuthController(
        httpClient: backend.httpClient, baseUrl: 'http://test.local');

      await auth.logout();

      expect(auth.isLoggedIn, isFalse);
    });
  });

  group('token 会被带上请求', () {
    test('登录请求本身不带 token', () async {
      final FakeBackend backend = FakeBackend()..seedAccount('xiaoming', 'hunter2hunter2');
      final AuthController auth = AuthController(
        httpClient: backend.httpClient,
        baseUrl: 'http://test.local',
        store: MemoryAuthStore(),
      );

      await auth.login(username: 'xiaoming', password: 'hunter2hunter2');

      expect(backend.authHeaders.single, isNull);
    });

    test('登录之后同一套客户端会带上 token', () async {
      // 这条守的是「界面显示已登录、请求却是匿名的」这类问题。
      // AuthController 和它内部那个 ApiClient 是两个对象，
      // token 有没有真的接下去，只有看请求头才知道 ——
      // 曾经这里接错了，表现是「每次打开 App 都要重新登录」，
      // 看起来完全像是后端的毛病。
      final FakeBackend backend = FakeBackend()..seedAccount('xiaoming', 'hunter2hunter2');
      final AuthController auth = AuthController(
        httpClient: backend.httpClient,
        baseUrl: 'http://test.local',
        store: MemoryAuthStore(),
      );
      await auth.login(username: 'xiaoming', password: 'hunter2hunter2');

      // restore() 会带着本地 token 去问 /api/auth/me。
      // 拿得回用户，就证明头确实带上了 —— 假后端没有 token 时返回 401。
      await auth.restore();

      expect(backend.authHeaders.last, 'Bearer ${auth.token}');
      expect(auth.isLoggedIn, isTrue, reason: '带上了 token，me 才可能成功');
    });
  });

  group('AuthUser 模型', () {
    test('没有昵称时显示用户名', () {
      const AuthUser user = AuthUser(id: 1, username: 'xiaoming');

      expect(user.displayName, 'xiaoming');
    });

    test('昵称为空串时也算没有昵称', () {
      // 后端存 "" 和存 null 在界面上应该是同一个结果
      const AuthUser user = AuthUser(id: 1, username: 'xiaoming', nickname: '  ');

      expect(user.displayName, 'xiaoming');
    });

    test('首字符用于头像占位', () {
      const AuthUser user = AuthUser(id: 1, username: 'xiaoming');

      expect(user.initial, 'x');
    });

    test('中文昵称的首字符取一个字，不是半个', () {
      const AuthUser user = AuthUser(id: 1, username: 'a', nickname: '小明');

      expect(user.initial, '小');
    });

    test('emoji 昵称不会被切坏', () {
      // 按 UTF-16 码元切会切出半个代理对，显示成乱码方块
      const AuthUser user = AuthUser(id: 1, username: 'a', nickname: '🙂开心');

      expect(user.initial, '🙂');
    });

    test('从 JSON 解析字段', () {
      final AuthUser user = AuthUser.fromJson(<String, dynamic>{
        'id': 7,
        'username': 'xiaoming',
        'nickname': '小明',
        'avatar_url': null,
        'study_days': 3,
      });

      expect(user.id, 7);
      expect(user.nickname, '小明');
      expect(user.studyDays, 3);
    });

    test('缺少可选字段时用默认值而不是崩掉', () {
      final AuthUser user = AuthUser.fromJson(<String, dynamic>{
        'id': 7,
        'username': 'xiaoming',
      });

      expect(user.nickname, isNull);
      expect(user.studyDays, 0);
    });
  });
}
