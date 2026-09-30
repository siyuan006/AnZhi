import 'package:anzhi/core/auth_controller.dart';
import 'package:anzhi/pages/ai_page.dart';
import 'package:anzhi/pages/community_page.dart';
import 'package:anzhi/pages/favorites_page.dart';
import 'package:anzhi/pages/history_page.dart';
import 'package:anzhi/pages/home_page.dart';
import 'package:anzhi/pages/knowledge_detail_page.dart';
import 'package:anzhi/pages/knowledge_page.dart';
import 'package:anzhi/pages/login_page.dart';
import 'package:anzhi/pages/my_posts_page.dart';
import 'package:anzhi/pages/post_compose_page.dart';
import 'package:anzhi/pages/post_detail_page.dart';
import 'package:anzhi/pages/profile_page.dart';
import 'package:anzhi/pages/settings_follow_page.dart';
import 'package:anzhi/pages/settings_home_page.dart';
import 'package:anzhi/pages/settings_notify_page.dart';
import 'package:anzhi/services/post_api.dart';
import 'package:anzhi/widgets/async_status.dart';
import 'package:anzhi/widgets/main_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fake_backend.dart';

const List<Size> _phoneSizes = <Size>[
  Size(320, 568),
  Size(360, 640),
  Size(411, 867),
];

const List<double> _textScales = <double>[1.0, 1.3, 1.5, 2.0];

const Set<String> _fetchesOnOpen = <String>{
  '首页',
  '主框架',
  '知识列表',
  '社区',
  '收藏',
  '浏览历史',
  '知识详情',
  '帖子详情',
  '我的帖子',
  '首页布局设置',
  '通知设置',
  '关注领域设置',
};

const Set<String> _emptyAble = <String>{
  '首页',
  '主框架',
  '知识列表',
  '社区',
  '收藏',
  '浏览历史',
  '知识详情',
  '帖子详情',
  '我的帖子',
};

void main() {
  Future<List<String>> collectLayoutErrors(
    WidgetTester tester,
    String name,
    String variant, {
    required Size size,
    required double scale,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final FakeBackend backend = FakeBackend()
      ..seedAccount('alice', 'hunter2hunter2', nickname: '小艾')
      ..seedFavorite('alice', 1)
      ..seedFavorite('alice', 2)
      ..seedHistory('alice', 1)
      ..seedHistory('alice', 2)
      ..seedSettings('alice', followedCategories: <int>[1]);

    final AuthController auth = backend.authController();
    await auth.login(username: 'alice', password: 'hunter2hunter2');

    switch (variant) {
      case 'error':
        backend.offline = true;
      case 'empty':
        backend
          ..items = <Map<String, dynamic>>[]
          ..seedNoPosts()
          ..seedNoComments();
        backend.favorites.clear();
        backend.histories.clear();
      case 'loading':
        backend.delay = const Duration(seconds: 5);
    }

    final Map<String, Widget> pages = <String, Widget>{
      '首页': HomePage(
        api: backend.api(),
        postApi: PostApi(client: auth.apiClient),
        settingsApi: auth.settingsApi,
      ),
      '主框架': MainScaffold(
        knowledgeApi: backend.api(),
        chatApi: backend.chatApi(),
        postApi: PostApi(client: auth.apiClient),
      ),
      '知识列表': KnowledgePage(api: backend.api()),
      'AI 问答': AiPage(api: backend.chatApi(), knowledgeApi: backend.api()),
      '社区': CommunityPage(api: backend.postApi()),
      '我的': const ProfilePage(),
      '收藏': FavoritesPage(api: auth.favoriteApi),
      '浏览历史': HistoryPage(api: auth.historyApi),
      '知识详情': KnowledgeDetailPage(
        knowledgeId: 1,
        api: backend.api(),
        favoriteApi: auth.favoriteApi,
      ),
      '帖子详情': PostDetailPage(postId: 1, api: backend.postApi()),
      '发帖': PostComposePage(api: PostApi(client: auth.apiClient)),
      '我的帖子': MyPostsPage(api: PostApi(client: auth.apiClient)),
      '登录': const LoginPage(),
      '首页布局设置': SettingsHomePage(api: auth.settingsApi),
      '通知设置': SettingsNotifyPage(api: auth.settingsApi),
      '关注领域设置': SettingsFollowPage(api: auth.settingsApi),
    };

    final List<FlutterErrorDetails> errors = <FlutterErrorDetails>[];
    final void Function(FlutterErrorDetails)? original = FlutterError.onError;
    FlutterError.onError = errors.add;

    String state = '';
    int errorCount = 0;
    int emptyCount = 0;
    int loadingCount = 0;
    int scaffoldCount = 0;
    int textCount = 0;
    try {
      await tester.pumpWidget(
        AuthScope(
          controller: auth,
          child: MaterialApp(
            builder: (BuildContext context, Widget? child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: pages[name],
          ),
        ),
      );

      if (variant == 'loading') {
        await tester.pump();
      } else {
        await tester.pumpAndSettle();
      }

      errorCount = find.byType(ErrorPlaceholder).evaluate().length;
      emptyCount = find.byType(EmptyPlaceholder).evaluate().length;
      loadingCount = find.byType(LoadingPlaceholder).evaluate().length;
      scaffoldCount = find.byType(Scaffold).evaluate().length;
      textCount = find.byType(Text).evaluate().length;
      state = 'err=$errorCount empty=$emptyCount loading=$loadingCount '
          'scaffold=$scaffoldCount text=$textCount';

      if (variant == 'loading') {
        backend.delay = null;
        await tester.pump(const Duration(seconds: 6));
      }
      await tester.pumpAndSettle();
    } finally {
      FlutterError.onError = original;
    }

    final List<String> problems = <String>[];
    for (final FlutterErrorDetails details in errors) {
      final String dump = details.toString();
      final RegExpMatch? spot =
          RegExp(r'(lib/[A-Za-z_/]+\.dart:\d+:\d+)').firstMatch(dump);
      final String location = spot == null ? '位置未知' : spot.group(1)!;
      problems.add(
        '$name（$variant，${size.width.toInt()}x${size.height.toInt()}，'
        '字号 x$scale）$location：${details.exceptionAsString()}',
      );
    }

    void wrongState(String expected) => problems.add(
          '$name（$variant，${size.width.toInt()}x${size.height.toInt()}，'
          '字号 x$scale）：$expected，实际 $state',
        );

    final bool fetches = _fetchesOnOpen.contains(name);

    if (scaffoldCount == 0) {
      wrongState('一个 Scaffold 都没有，页面根本没建起来');
    }

    switch (variant) {
      case 'ok':
        if (errorCount > 0 || emptyCount > 0 || loadingCount > 0) {
          wrongState('数据正常时不该出现失败 / 空 / 加载占位');
        }
        if (textCount < 3) {
          wrongState('正常的页面至少该有几个文字，实际几乎没有内容');
        }
      case 'error':
        if (fetches && errorCount == 0) {
          wrongState('后端不可用时必须显示失败占位，不能留白或谎称「暂无内容」');
        }
        if (!fetches && errorCount > 0) {
          wrongState('这一页不联网，不该凭空冒出失败占位');
        }
      case 'empty':
        if (_emptyAble.contains(name) && errorCount + emptyCount == 0) {
          wrongState('后端返回空数据时要说明是空的（或那条数据已不存在）');
        }
      case 'loading':
        if (fetches && loadingCount == 0) {
          wrongState('等待数据时应当有加载占位，而不是一片空白');
        }
      default:
        wrongState('未知状态');
    }

    return problems;
  }

  testWidgets('手机尺寸与放大字号下不出现布局溢出', (WidgetTester tester) async {
    final List<String> problems = <String>[];
    const List<String> pages = <String>[
      '首页', '主框架', '知识列表', 'AI 问答', '社区', '我的', '收藏', '浏览历史',
      '知识详情', '帖子详情', '发帖', '我的帖子', '登录',
      '首页布局设置', '通知设置', '关注领域设置',
    ];
    const List<String> variants = <String>['ok', 'error', 'empty', 'loading'];

    for (final Size size in _phoneSizes) {
      for (final double scale in _textScales) {
        for (final String variant in variants) {
          for (final String page in pages) {
            problems.addAll(
              await collectLayoutErrors(tester, page, variant,
                  size: size, scale: scale),
            );
          }
        }
      }
    }

    expect(
      problems,
      isEmpty,
      reason: '布局溢出会把内容裁掉，用户看到的是黄黑条纹或缺失的文字',
    );
  });
}
