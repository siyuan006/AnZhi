import 'package:flutter/material.dart';

/// 安知 —— 全局常量定义
///
/// 依据 PROJECT_SPEC.md：
///   - 第四节：V1.0 固定六大安全知识分类
///   - 第十节：三级风险系统

// ---------------------------------------------------------------------------
// 应用信息
// ---------------------------------------------------------------------------

const String kAppName = '安知';
const String kAppSlogan = 'AI 安全知识科普助手';
const String kAppVersion = '1.0.0';

// ---------------------------------------------------------------------------
// 风险等级（PROJECT_SPEC 第十节）
// ---------------------------------------------------------------------------

/// 三级风险系统。
///
/// [value] 必须与后端 API 及数据库 `knowledge.risk_level` 字段保持一致，
/// 否则前后端解析会出错。
enum RiskLevel {
  low('low', '低风险', Color(0xFF2E7D32), Icons.check_circle_outline),
  medium('medium', '中风险', Color(0xFFEF6C00), Icons.warning_amber_rounded),
  high('high', '高风险', Color(0xFFC62828), Icons.dangerous_outlined);

  const RiskLevel(this.value, this.label, this.color, this.icon);

  /// 序列化值，与后端 / 数据库一致
  final String value;

  /// 中文显示名
  final String label;

  /// 风险主题色
  final Color color;

  /// 风险图标
  final IconData icon;

  /// 从后端返回值解析，无法识别时回退为 [RiskLevel.low]
  static RiskLevel fromValue(String? value) {
    return RiskLevel.values.firstWhere(
      (level) => level.value == value,
      orElse: () => RiskLevel.low,
    );
  }
}

// ---------------------------------------------------------------------------
// 安全知识分类（PROJECT_SPEC 第四节）
// ---------------------------------------------------------------------------

/// 一个安全知识分类。
class SafetyCategory {
  const SafetyCategory({
    required this.id,
    required this.name,
    required this.slug,
    required this.icon,
    required this.color,
    required this.description,
  });

  /// 对应数据库 `categories.id`
  final int id;
  final String name;

  /// 英文标识，供前端路由与图标映射使用
  final String slug;
  final IconData icon;
  final Color color;
  final String description;
}

/// V1.0 六大分类。
///
/// 与 `docs/DATABASE.md` 中 `categories` 表的种子数据严格一一对应，
/// 修改任意一侧都必须同步另一侧。
const List<SafetyCategory> kCategories = <SafetyCategory>[
  SafetyCategory(
    id: 1,
    name: '消防安全',
    slug: 'fire',
    icon: Icons.local_fire_department_outlined,
    color: Color(0xFFE53935),
    description: '火灾预防、灭火器使用、火场逃生',
  ),
  SafetyCategory(
    id: 2,
    name: '用电安全',
    slug: 'electric',
    icon: Icons.bolt_outlined,
    color: Color(0xFFFB8C00),
    description: '插座安全、电动车充电、触电急救',
  ),
  SafetyCategory(
    id: 3,
    name: '交通安全',
    slug: 'traffic',
    icon: Icons.directions_car_outlined,
    color: Color(0xFF1E88E5),
    description: '行人、骑行、驾驶与事故处理',
  ),
  SafetyCategory(
    id: 4,
    name: '校园安全',
    slug: 'campus',
    icon: Icons.school_outlined,
    color: Color(0xFF43A047),
    description: '宿舍、实验室、体育运动安全',
  ),
  SafetyCategory(
    id: 5,
    name: '网络与反诈安全',
    slug: 'cyber',
    icon: Icons.shield_outlined,
    color: Color(0xFF8E24AA),
    description: '电信诈骗、钓鱼网站、隐私保护',
  ),
  SafetyCategory(
    id: 6,
    name: '自然灾害与应急',
    slug: 'disaster',
    icon: Icons.tsunami_outlined,
    color: Color(0xFF00897B),
    description: '地震、洪水、台风与应急避险',
  ),
];

/// 按 [id] 查找分类，找不到返回 `null`
SafetyCategory? categoryById(int id) {
  for (final category in kCategories) {
    if (category.id == id) return category;
  }
  return null;
}

// ---------------------------------------------------------------------------
// 首页模块标识（PROJECT_SPEC 第十九节：个性化首页）
// ---------------------------------------------------------------------------

/// 首页可显示 / 隐藏的模块标识，与用户设置中的 `home_modules` 对应。
///
/// ⚠️ [id] 是**接口契约**，必须与后端
/// `backend/app/services/personalization/settings_service.py` 的
/// `HOME_MODULES` 一致。和 `kCategories` 与 `categories.id` 的关系一样：
/// 两边对不上时不会有任何报错，只会「设置无效」——
/// 用户在首页布局里关掉一个模块，保存成功，首页却毫无变化。
class HomeModule {
  const HomeModule(this.id, this.label);

  final String id;
  final String label;

  static const HomeModule daily = HomeModule('daily', '今日安全知识');
  static const HomeModule recommend = HomeModule('recommend', '推荐知识');
  static const HomeModule category = HomeModule('category', '安全分类');
  static const HomeModule ai = HomeModule('ai', 'AI 助手');
  static const HomeModule community = HomeModule('community', '社区精选');

  /// 顺序即首页从上到下的排布（PROJECT_SPEC 第七节），
  /// 也与后端存 `home_modules` 时用的规范顺序一致 ——
  /// 「首页布局」页面直接按这个顺序列，用户看到的就是首页的样子。
  static const List<HomeModule> all = <HomeModule>[
    daily,
    recommend,
    category,
    ai,
    community,
  ];
}

/// 按 [id] 查找首页模块，找不到返回 `null`。
///
/// 返回 `null` 而不是某个默认模块：后端将来加了新模块而客户端还没跟上时，
/// 猜一个只会让设置页显示错误的开关状态。
HomeModule? homeModuleById(String id) {
  for (final module in HomeModule.all) {
    if (module.id == id) return module;
  }
  return null;
}

// ---------------------------------------------------------------------------
// 布局常量
// ---------------------------------------------------------------------------

/// 页面水平内边距
const double kPagePadding = 16.0;

/// 卡片圆角
const double kCardRadius = 14.0;

/// 卡片间距
const double kCardGap = 12.0;
