import 'app_constants.dart';

/// ⚠️ 占位数据 —— 临时文件，阶段 12 后端社区接口完成后删除 ⚠️
///
/// 本文件仅用于社区接口完成前让 UI 有内容可渲染，
/// **不是真实接口返回的数据**。
///
/// 阶段 7「前后端通信」已完成：知识卡片与分类已改由
/// `lib/services/knowledge_api.dart` 调用真实后端接口，
/// 原 `kSampleKnowledge` 等知识占位数据**已随本次改动删除**。
///
/// 目前仅剩社区帖子占位，因为社区接口（`GET /api/posts`）属阶段 12。
/// 阶段 12 完成后：
///   1. 帖子改由 `services/post_api.dart` 拉取
///   2. 本文件整体删除
///
/// 禁止将本文件的占位内容当作已完成的接口功能对外宣称。

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

/// 首页「社区精选」—— 占位
List<SamplePost> get kSampleFeaturedPosts => kSamplePosts;
