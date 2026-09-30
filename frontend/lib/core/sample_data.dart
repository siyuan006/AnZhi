import '../models/knowledge_item.dart';
import 'app_constants.dart';

/// ⚠️ 占位数据 —— 临时文件，后端接通后删除 ⚠️
///
/// 本文件仅用于在 FastAPI 后端完成前（阶段 3~6）让 UI 有内容可渲染，
/// **不是真实接口返回的数据**，也不是真实知识库内容。
///
/// 阶段 7「前后端通信」完成后：
///   1. 由 `lib/services/api_client.dart` 发起真实 HTTP 请求
///   2. 本文件整体删除
///   3. 页面改为消费 `services/` 返回的数据
///
/// 禁止将本文件的占位内容当作已完成的接口功能对外宣称。

/// 占位知识卡片
const List<KnowledgeItem> kSampleKnowledge = <KnowledgeItem>[
  KnowledgeItem(
    id: 1,
    title: '宿舍发生火灾如何正确逃生',
    categoryId: 1,
    summary: '保持冷静、低姿撤离、不乘电梯、不贪恋财物。掌握正确的逃生方式能在关键时刻救命。',
    riskLevel: RiskLevel.high,
    viewCount: 128,
  ),
  KnowledgeItem(
    id: 2,
    title: '电动车为什么不能在楼道充电',
    categoryId: 2,
    summary: '锂电池起火 3 分钟即可产生致命浓烟，楼道充电会直接封死唯一逃生通道。',
    riskLevel: RiskLevel.high,
    viewCount: 256,
  ),
  KnowledgeItem(
    id: 3,
    title: '灭火器的四种常见类型与适用范围',
    categoryId: 1,
    summary: '干粉、二氧化碳、水基、泡沫灭火器各有适用场景，用错反而会助长火势。',
    riskLevel: RiskLevel.low,
    viewCount: 89,
  ),
  KnowledgeItem(
    id: 4,
    title: '识别电信诈骗的五个通用信号',
    categoryId: 5,
    summary: '要求转账、索要验证码、自称公检法、制造紧迫感、要求屏幕共享——出现任意一条都要警惕。',
    riskLevel: RiskLevel.medium,
    viewCount: 312,
  ),
  KnowledgeItem(
    id: 5,
    title: '地震发生时室内避险要点',
    categoryId: 6,
    summary: '伏地、遮挡、手抓牢。优先选择承重墙角或坚固桌下，远离玻璃与外墙。',
    riskLevel: RiskLevel.high,
    viewCount: 174,
  ),
  KnowledgeItem(
    id: 6,
    title: '校园实验室常见安全隐患',
    categoryId: 4,
    summary: '化学品存放、用电负荷、通风设施、应急冲洗装置是实验室检查的四个重点。',
    riskLevel: RiskLevel.medium,
    viewCount: 67,
  ),
  KnowledgeItem(
    id: 7,
    title: '夜间骑行电动车的安全装备',
    categoryId: 3,
    summary: '头盔、反光条、前后车灯是夜间骑行的最低配置，缺一不可。',
    riskLevel: RiskLevel.low,
    viewCount: 143,
  ),
  KnowledgeItem(
    id: 8,
    title: '插座冒烟时的正确处理方式',
    categoryId: 2,
    summary: '立即断开总闸，切勿直接用手拔插头或用泼水方式处理。',
    riskLevel: RiskLevel.medium,
    viewCount: 201,
  ),
];

/// 占位社区帖子
class SamplePost {
  const SamplePost({
    required this.id,
    required this.author,
    required this.title,
    required this.content,
    required this.categoryId,
    required this.likeCount,
    required this.commentCount,
  });

  final int id;
  final String author;
  final String title;
  final String content;
  final int categoryId;
  final int likeCount;
  final int commentCount;

  SafetyCategory? get category => categoryById(categoryId);
}

/// 占位社区帖子列表
const List<SamplePost> kSamplePosts = <SamplePost>[
  SamplePost(
    id: 1,
    author: '安全小卫士',
    title: '宿舍插座一直发烫，换了一个还是这样，求助',
    content: '换了新插座还是发烫，怀疑是线路问题。有没有懂的同学说说该怎么排查？',
    categoryId: 2,
    likeCount: 24,
    commentCount: 8,
  ),
  SamplePost(
    id: 2,
    author: '反诈小分队',
    title: '刚接到一个冒充客服的电话，分享下识别过程',
    content: '对方能报出我的订单号，差点就信了。关键破绽是让我开屏幕共享。',
    categoryId: 5,
    likeCount: 156,
    commentCount: 32,
  ),
  SamplePost(
    id: 3,
    author: '实验室常客',
    title: '实验室安全考试笔记整理',
    content: '整理了老师上课强调的重点，包括危化品分类、应急冲洗流程等。',
    categoryId: 4,
    likeCount: 88,
    commentCount: 15,
  ),
];

/// 首页「今日安全知识」—— 占位，实际应由后端按日期选取
KnowledgeItem get kSampleDailyKnowledge => kSampleKnowledge.first;

/// 首页「推荐知识」—— 占位，V1.0 使用固定推荐（PROJECT_SPEC 第七节）
List<KnowledgeItem> get kSampleRecommended => kSampleKnowledge.take(4).toList();

/// 首页「社区精选」—— 占位
List<SamplePost> get kSampleFeaturedPosts => kSamplePosts;
