import 'package:anzhi/core/app_constants.dart';
import 'package:anzhi/models/knowledge_item.dart';
import 'package:anzhi/models/paged_result.dart';
import 'package:anzhi/services/api_client.dart';
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
    },
    skip: enabled
        ? false
        : '需要运行中的后端，用 --dart-define=ANZHI_LIVE_BACKEND=true 开启',
  );

  tearDownAll(api.dispose);
}
