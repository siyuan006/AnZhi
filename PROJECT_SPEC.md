# 安知——AI安全知识科普助手

> 项目代号：AnZhi
> 项目类型：AI + 安全知识科普 + Android App
> 开发模式：AI 辅助开发 + 人工审核
> 开发者：个人开发
> 项目周期：约 1 个月完成 MVP
> 最终平台：Android
> 项目目标：真实项目 + GitHub 开源展示 + 实习项目经历

---

# 一、AI开发总规则

你是本项目的 AI 技术开发助手。

你的任务不是一次性生成整个项目，而是：

1. 分阶段开发
2. 每次只完成当前阶段
3. 先分析，再修改代码
4. 不随意改变已经确定的项目架构
5. 不删除已有功能
6. 修改代码后说明修改了什么
7. 每完成一个阶段都进行测试
8. 遇到错误先定位原因，再修改
9. 不生成未经验证的大量代码
10. 所有涉及安全知识的内容必须谨慎处理
11. API Key、密码、Token 等敏感信息禁止写入代码仓库
12. 不允许为了“看起来完成”而伪造接口、数据或测试结果

---

# 二、项目背景

项目名称：

> 安知——AI安全知识科普助手

项目定位：

面向普通用户和大学生的 AI 安全知识科普 Android App。

用户可以通过：

* AI 问答
* 安全知识卡片
* 安全知识分类
* 个性化推荐
* 社区交流
* 收藏
* 历史记录
* 个性化首页

学习安全知识。

项目结合安全工程专业知识与人工智能技术。

---

# 三、目标用户

第一阶段主要面向：

1. 普通用户
2. 大学生

主要使用场景：

* 学习日常安全知识
* 查询安全问题
* 遇到突发情况时获取基础应急信息
* 学习消防安全
* 学习用电安全
* 学习交通安全
* 学习校园安全
* 学习网络诈骗防范
* 学习自然灾害与应急知识

---

# 四、安全知识分类

V1.0 固定使用以下六个分类：

## 1. 消防安全

例如：

* 火灾预防
* 灭火器使用
* 火灾逃生
* 烟雾报警器
* 高层建筑火灾
* 宿舍消防

---

## 2. 用电安全

例如：

* 插座安全
* 电动车充电
* 宿舍用电
* 电器短路
* 触电急救
* 电气火灾

---

## 3. 交通安全

例如：

* 行人安全
* 骑行安全
* 电动车安全
* 驾驶安全
* 交通事故处理
* 夜间出行

---

## 4. 校园安全

例如：

* 宿舍安全
* 实验室安全
* 体育运动安全
* 校园欺凌
* 食品安全
* 校园突发事件

---

## 5. 网络与反诈安全

例如：

* 电信诈骗
* 网络诈骗
* 钓鱼网站
* 网络账号安全
* 密码安全
* 隐私保护
* AI诈骗

---

## 6. 自然灾害与应急

例如：

* 地震
* 洪水
* 台风
* 雷电
* 暴雨
* 高温
* 应急避险
* 应急物资

---

# 五、未来可扩展分类

V1.0 暂时不要开发。

未来可以加入：

* 危险化学品安全
* 生产安全
* 建筑施工安全
* 食品安全
* 职业安全
* 公共安全
* 特种设备安全
* 实验室安全

---

# 六、V1.0 页面结构

底部导航固定为：

```text
首页
AI
知识
社区
我的
```

---

# 七、首页

首页主要展示：

```text
顶部
↓
今日安全知识
↓
推荐知识卡片
↓
安全分类
↓
AI助手入口
↓
社区精选
```

V1.0 暂时不实现复杂推荐算法。

先使用：

```text
固定推荐
+
简单用户兴趣
```

后续再增加 AI 个性化推荐。

---

# 八、AI页面

AI页面是项目核心功能之一。

用户可以输入：

```text
宿舍发生火灾应该怎么办？
```

或者：

```text
电动车可以在楼道充电吗？
```

AI进行回答。

---

# 九、AI回答结构

AI回答不能只返回普通文本。

未来标准结构：

```json
{
    "question": "宿舍发生火灾怎么办？",
    "category": "消防安全",
    "risk_level": "high",
    "answer": "......",
    "steps": [
        "......",
        "......",
        "......"
    ],
    "sources": [
        "......"
    ],
    "warning": "......"
}
```

---

# 十、风险等级

项目使用三级风险系统。

## 🟢 LOW

普通安全知识。

例如：

```text
灭火器有哪些种类？
```

处理：

正常科普。

---

## 🟡 MEDIUM

需要注意安全风险的问题。

例如：

```text
插座冒烟怎么办？
```

处理：

强调不要继续操作，并给出安全建议。

---

## 🔴 HIGH

紧急、高风险问题。

例如：

```text
现在家里着火怎么办？
```

处理原则：

1. 回答简洁
2. 优先说明立即采取的安全措施
3. 不提供危险操作
4. 不鼓励用户冒险
5. 必要时建议联系当地专业救援/紧急服务
6. 不进行长篇科普

---

# 十一、AI安全原则

AI回答安全问题时必须遵循：

```text
生命安全优先
↓
避免危险操作
↓
给出可执行步骤
↓
必要时建议寻求专业帮助
↓
最后再进行知识解释
```

高风险问题禁止：

* 鼓励用户进入危险区域
* 提供危险实验步骤
* 提供可能导致伤害的操作
* 对紧急情况进行娱乐化回答
* 给出过度自信的判断

---

# 十二、AI技术架构

V1.0：

```text
Flutter
   ↓
FastAPI
   ↓
AI Service
   ↓
DeepSeek API
   ↓
返回结果
```

未来：

```text
Flutter
   ↓
FastAPI
   ↓
Agent Service
   ↓
问题分类
   ↓
Risk Service
   ↓
风险判断
   ↓
RAG Service
   ↓
安全知识库
   ↓
DeepSeek
   ↓
Safety Guard
   ↓
最终回答
```

---

# 十三、AI服务模块

后端预留以下结构：

```text
AI Service

├── ChatService
├── AgentService
├── RiskService
├── RAGService
└── SafetyGuard
```

V1.0：

```text
ChatService
    ↓
DeepSeek
```

后续逐步增加其他模块。

---

# 十四、RAG规划

不要在项目第一天就实现复杂RAG。

采用渐进式开发。

## V1.0

```text
用户问题
↓
FastAPI
↓
DeepSeek
↓
回答
```

---

## V1.5

加入：

```text
安全知识库
↓
知识检索
↓
DeepSeek
```

---

## V2.0

完整：

```text
用户问题
↓
问题分类
↓
风险判断
↓
知识检索
↓
RAG
↓
DeepSeek
↓
Safety Guard
↓
回答
↓
引用来源
```

---

# 十五、知识库

知识卡片由：

```text
AI生成初稿
↓
人工审核
↓
发布
```

禁止直接让AI生成内容后自动发布高风险安全知识。

---

# 十六、知识卡片结构

每个知识卡片至少包含：

```text
标题
分类
简介
正文
风险等级
图片
来源
发布时间
作者
```

数据库字段建议：

```text
id
title
category_id
summary
content
risk_level
image_url
source
created_at
updated_at
```

---

# 十七、知识卡片图片

图片允许使用：

```text
AI生成
+
自行制作
+
合法授权素材
+
公共版权资源
```

必须注意版权问题。

禁止直接使用无法确认版权的网络图片作为公开项目素材。

---

# 十八、个性化推荐

系统记录：

```text
浏览记录
收藏记录
AI提问
点赞
关注分类
```

生成简单兴趣标签：

例如：

```text
消防安全：0.8
网络安全：0.6
交通安全：0.2
```

然后推荐相关内容。

V1.0 可以先使用简单规则。

例如：

```text
用户收藏消防安全
↓
提高消防安全推荐权重
```

以后再加入机器学习或AI推荐。

---

# 十九、个性化首页

用户可以自己设置首页。

V1.0支持：

```text
显示/隐藏模块
选择关注分类
```

未来支持：

```text
拖动模块
调整顺序
调整卡片样式
```

例如：

```text
我的首页

[今日安全知识]
[AI助手]
[消防安全]
[社区]
```

用户可以调整为：

```text
[AI助手]
[反诈知识]
[今日安全知识]
[社区]
```

---

# 二十、社区

V1.0社区保持轻量。

支持：

```text
帖子列表
帖子详情
发布帖子
评论
点赞
```

暂时不实现：

```text
私信
关注用户
复杂推荐
AI审核
```

---

# 二十一、社区未来AI功能

未来增加：

```text
AI内容审核
↓
风险识别
↓
内容分类
↓
违规内容检测
↓
优质内容识别
```

优质安全内容未来可以：

```text
社区帖子
↓
AI筛选
↓
人工审核
↓
知识卡片候选
```

---

# 二十二、我的页面

包含：

```text
个人信息
学习天数
收藏
历史记录
我的帖子
关注领域
首页布局
通知设置
关于安知
```

---

# 二十三、数据库设计

V1.0主要数据表：

```text
User
Category
Knowledge
Favorite
History
Post
Comment
Like
UserSettings
```

---

# 二十四、数据库关系

```text
User
 │
 ├── Favorite ── Knowledge
 │
 ├── History ─── Knowledge
 │
 ├── Post
 │      │
 │      ├── Comment
 │      └── Like
 │
 └── UserSettings
```

---

# 二十五、技术栈

## Android前端

使用：

```text
Flutter
```

语言：

```text
Dart
```

---

## 后端

使用：

```text
Python
FastAPI
```

---

## AI

使用：

```text
DeepSeek API
```

---

## 数据库

V1.0：

```text
SQLite
```

后续：

```text
PostgreSQL
```

---

## RAG

后续：

```text
Embedding
+
Vector Database
```

具体向量数据库根据实际开发阶段决定。

---

## 版本管理

```text
Git
GitHub
```

---

# 二十六、项目目录

目标目录：

```text
AnZhi/
│
├── frontend/
│   └── Flutter项目
│
├── backend/
│   ├── app/
│   │   ├── main.py
│   │   ├── api/
│   │   ├── models/
│   │   ├── schemas/
│   │   ├── services/
│   │   │   ├── ai/
│   │   │   │   ├── chat_service.py
│   │   │   │   ├── agent_service.py
│   │   │   │   ├── risk_service.py
│   │   │   │   ├── rag_service.py
│   │   │   │   └── safety_guard.py
│   │   │   └── knowledge/
│   │   ├── database/
│   │   └── config/
│   │
│   ├── tests/
│   ├── requirements.txt
│   └── .env.example
│
├── docs/
│   ├── PRD.md
│   ├── ARCHITECTURE.md
│   ├── API.md
│   └── DATABASE.md
│
├── assets/
│
├── .gitignore
├── README.md
└── PROJECT_SPEC.md
```

---

# 二十七、开发阶段总流程

必须按照以下顺序开发。

```text
阶段1：开发环境
↓
阶段2：GitHub仓库
↓
阶段3：Flutter项目
↓
阶段4：Flutter页面
↓
阶段5：FastAPI后端
↓
阶段6：数据库
↓
阶段7：前后端通信
↓
阶段8：DeepSeek
↓
阶段9：AI安全控制
↓
阶段10：知识系统
↓
阶段11：收藏/历史
↓
阶段12：社区
↓
阶段13：个性化
↓
阶段14：RAG
↓
阶段15：测试
↓
阶段16：UI优化
↓
阶段17：APK打包
↓
阶段18：GitHub发布
```

---

# 二十八、第一阶段：开发环境

检查：

```text
Git
Flutter
Dart
Android Studio
Android SDK
Python
PyCharm
VS Code
```

AI需要帮助用户检查：

```text
flutter --version
dart --version
python --version
git --version
```

如果缺少环境：

1. 不要直接进入项目开发
2. 先帮助用户安装
3. 安装完成后验证
4. 验证成功再继续

---

# 二十九、第二阶段：GitHub

创建：

```text
AnZhi
```

GitHub仓库。

初始化：

```bash
git init
git add .
git commit -m "init: initialize AnZhi project"
git branch -M main
git remote add origin <repository-url>
git push -u origin main
```

之后采用：

```text
feat:
fix:
refactor:
docs:
test:
chore:
```

作为Commit前缀。

---

# 三十、第三阶段：Flutter项目

创建Flutter Android项目。

目标：

```text
启动App
↓
显示安知首页
↓
底部导航
↓
5个页面可以切换
```

五个页面：

```text
HomePage
AIPage
KnowledgePage
CommunityPage
ProfilePage
```

第一阶段不要接后端。

---

# 三十一、第四阶段：Flutter UI

优先完成：

```text
底部导航
首页
AI页面
知识页面
社区页面
我的页面
```

UI原则：

```text
简洁
现代
安全感
信息清晰
适合大学生
```

不要一开始追求复杂动画。

---

# 三十二、第五阶段：FastAPI

创建：

```text
backend/
```

安装：

```text
fastapi
uvicorn
sqlalchemy
python-dotenv
```

创建：

```text
main.py
```

实现：

```text
GET /
```

返回：

```json
{
    "message": "AnZhi API is running"
}
```

运行：

```bash
uvicorn app.main:app --reload
```

确认：

```text
后端启动成功
```

再进入下一阶段。

---

# 三十三、第六阶段：数据库

先创建SQLite。

数据库：

```text
anzhi.db
```

先实现：

```text
User
Category
Knowledge
```

再实现：

```text
Favorite
History
```

最后：

```text
Post
Comment
Like
UserSettings
```

不要一次性创建全部复杂数据库。

---

# 三十四、第七阶段：前后端通信

Flutter：

```text
HTTP Request
```

发送到：

```text
FastAPI
```

例如：

```text
GET /api/knowledge
```

返回：

```json
[
    {
        "id": 1,
        "title": "宿舍消防安全",
        "category": "消防安全"
    }
]
```

Flutter显示。

---

# 三十五、第八阶段：DeepSeek

DeepSeek API Key：

```text
禁止写进Flutter代码
禁止提交GitHub
禁止写入README
禁止硬编码
```

正确结构：

```text
Flutter
↓
FastAPI
↓
环境变量
↓
DeepSeek API
```

例如：

```text
.env
```

保存：

```text
DEEPSEEK_API_KEY=xxxxx
```

Git：

```text
.gitignore
```

必须包含：

```text
.env
```

---

# 三十六、AI问答第一版

实现：

```text
用户输入
↓
Flutter
↓
POST /api/chat
↓
FastAPI
↓
ChatService
↓
DeepSeek
↓
返回回答
↓
Flutter显示
```

API：

```text
POST /api/chat
```

请求：

```json
{
    "message": "宿舍着火怎么办？"
}
```

---

# 三十七、AI安全控制

不要让DeepSeek直接把结果原样返回。

流程：

```text
用户问题
↓
风险判断
↓
DeepSeek
↓
SafetyGuard
↓
最终回答
```

SafetyGuard负责：

```text
检查回答
检查高风险内容
检查危险操作
检查是否需要警告
```

---

# 三十八、知识系统

实现：

```text
分类列表
↓
知识列表
↓
知识详情
```

六大分类：

```text
消防
用电
交通
校园
网络反诈
自然灾害
```

---

# 三十九、收藏

实现：

```text
知识详情
↓
收藏按钮
↓
Favorite
```

我的：

```text
我的收藏
```

显示收藏内容。

---

# 四十、历史记录

用户：

```text
查看知识
```

自动记录：

```text
History
```

我的：

```text
浏览历史
```

---

# 四十一、社区

实现：

```text
帖子列表
↓
帖子详情
↓
评论
↓
点赞
```

最后实现：

```text
发布帖子
```

---

# 四十二、个性化

V1.0：

```text
关注分类
+
显示/隐藏首页模块
```

例如：

```text
消防
反诈
用电
```

用户关注：

```text
消防
反诈
```

首页优先显示：

```text
消防知识
反诈知识
```

---

# 四十三、RAG

V1.0完成之后再实现。

流程：

```text
安全资料
↓
文本清洗
↓
文本切分
↓
Embedding
↓
向量数据库
↓
用户问题
↓
向量检索
↓
相关知识
↓
DeepSeek
↓
回答
```

最终回答增加：

```text
参考来源
```

---

# 四十四、测试

每完成一个模块都必须测试。

测试分：

## 单元测试

例如：

```text
风险判断
数据库操作
AI服务
```

---

## API测试

测试：

```text
GET
POST
PUT
DELETE
```

---

## Flutter测试

检查：

```text
页面
按钮
导航
网络请求
异常情况
```

---

## 集成测试

测试完整流程：

```text
打开App
↓
进入AI
↓
提问
↓
FastAPI
↓
DeepSeek
↓
返回回答
```

---

# 四十五、异常情况测试

必须测试：

```text
网络断开
API超时
DeepSeek不可用
数据库错误
用户输入为空
用户输入过长
非法请求
服务器异常
```

不能出现：

```text
App直接崩溃
```

---

# 四十六、API安全

必须：

```text
API Key服务器保存
```

不能：

```text
Flutter保存API Key
GitHub提交API Key
README暴露API Key
```

加入：

```text
.env
.env.example
```

`.env.example`：

```text
DEEPSEEK_API_KEY=
```

---

# 四十七、GitHub发布

最终仓库：

```text
AnZhi
```

必须包含：

```text
README.md
PROJECT_SPEC.md
docs/
frontend/
backend/
assets/
```

README需要介绍：

```text
项目简介
功能
技术栈
项目架构
运行方法
截图
API配置
开发计划
未来规划
```

---

# 四十八、APK打包

最终：

```text
Flutter
↓
Android APK
```

生成Release版本。

APK最终作为：

```text
GitHub Release
```

附件发布。

用户可以：

```text
GitHub
↓
Release
↓
下载APK
↓
Android安装
```

---

# 四十九、项目最终成果

最终项目至少应该拥有：

```text
Android APK
GitHub仓库
完整README
项目架构文档
API文档
数据库设计
AI问答
安全知识库
知识卡片
收藏
历史
社区
个性化首页
风险等级
RAG
```

---

# 五十、AI编码规范

AI生成代码必须：

1. 使用清晰命名
2. 不随意使用全局变量
3. 减少重复代码
4. 模块化
5. 添加必要注释
6. 处理异常
7. 保持代码可维护
8. 不为了减少代码量而破坏结构
9. 不修改无关文件
10. 修改已有功能时保持兼容

---

# 五十一、Flutter代码规范

推荐结构：

```text
lib/
├── main.dart
├── app.dart
├── core/
├── models/
├── services/
├── pages/
├── widgets/
└── utils/
```

页面不要全部写进：

```text
main.dart
```

---

# 五十二、FastAPI代码规范

不要把所有代码写入：

```text
main.py
```

采用：

```text
api
models
schemas
services
database
config
```

分层。

---

# 五十三、AI开发规则

当用户说：

```text
下一步
```

AI应该：

1. 查看当前项目进度
2. 判断上一步是否完成
3. 确认依赖是否满足
4. 给出下一步
5. 一次只推进一个主要任务
6. 提供需要执行的命令
7. 提供代码
8. 解释代码
9. 告诉用户如何测试
10. 等待测试结果

---

# 五十四、遇到错误时

用户提供错误信息后：

不要直接重写整个项目。

必须：

```text
1. 分析错误
2. 判断错误位置
3. 解释原因
4. 给出最小修改
5. 修改后重新测试
```

---

# 五十五、禁止事项

AI不得：

```text
擅自更换Flutter
擅自更换FastAPI
擅自更换DeepSeek
擅自删除功能
擅自重构整个项目
擅自增加复杂技术
```

如果认为架构需要调整：

```text
先说明原因
↓
说明影响
↓
等待用户确认
```

---

# 五十六、开发顺序总表

```text
[ ] 1. 配置开发环境
[ ] 2. 创建GitHub仓库
[ ] 3. 创建Flutter项目
[ ] 4. 创建5个页面
[ ] 5. 完成底部导航
[ ] 6. 创建FastAPI
[ ] 7. 创建SQLite
[ ] 8. 创建基础数据模型
[ ] 9. 前后端通信
[ ] 10. 接入DeepSeek
[ ] 11. 完成AI聊天
[ ] 12. 增加AI安全控制
[ ] 13. 完成知识系统
[ ] 14. 完成收藏
[ ] 15. 完成历史记录
[ ] 16. 完成社区
[ ] 17. 完成个性化
[ ] 18. 实现RAG
[ ] 19. 完成风险等级
[ ] 20. 完善来源引用
[ ] 21. 测试
[ ] 22. UI优化
[ ] 23. 性能优化
[ ] 24. 安全检查
[ ] 25. APK打包
[ ] 26. 编写README
[ ] 27. GitHub Release
[ ] 28. 项目最终验收
```

---

# 五十七、项目开发验收标准

项目不能以：

```text
代码能运行
```

作为唯一完成标准。

最终必须满足：

```text
功能完成
+
代码结构合理
+
异常处理
+
安全处理
+
测试通过
+
README完整
+
GitHub可运行
+
APK可以安装
```

---

# 五十八、AI每次开发的输出格式

以后AI帮助开发本项目时，尽量按照以下格式：

```text
# 当前阶段

当前正在开发什么。

# 本次目标

本次只完成什么。

# 为什么

解释技术选择。

# 操作步骤

一步一步执行。

# 代码

只提供本次需要的代码。

# 测试

告诉用户如何测试。

# 预期结果

告诉用户正确结果。

# 常见错误

列出可能出现的问题。

# 完成后

告诉用户下一步是什么。
```

---

# 五十九、当前项目状态

当前状态：

```text
项目规划：已完成
PRD：已完成
技术架构：已确定
数据库设计：初步完成
页面规划：已完成
AI架构：已完成
RAG规划：已完成

实际代码：

尚未正式开始
```

---

# 六十、当前第一步

现在不要直接开发AI。

第一步：

```text
检查开发环境
```

然后：

```text
创建GitHub仓库
↓
创建Flutter项目
↓
运行默认App
```

确认Flutter开发环境没有问题之后，再进入：

```text
Flutter页面开发
```

---

# 六十一、最终开发路线

```text
              安知
               │
       ┌───────┴───────┐
       │               │
    Flutter          FastAPI
       │               │
       │          ┌────┴────┐
       │          │         │
       │       Database   AI Service
       │                    │
       │              ┌─────┴─────┐
       │              │           │
       │          DeepSeek       RAG
       │
       └──────── API ─────────────┘
                     │
                  安知App
                     │
       ┌─────────────┼─────────────┐
       │             │             │
      AI          知识          社区
       │             │             │
       └─────────────┼─────────────┘
                     │
                  个性化
                     │
                  用户学习
```

---

# 六十二、开发目标

最终将“安知”开发成一个：

> **基于 Flutter + FastAPI + DeepSeek + RAG 的 AI 安全知识科普 Android 应用。**

项目不仅追求功能能够运行，还需要体现：

```text
软件工程能力
+
Python后端能力
+
Flutter移动端能力
+
AI应用开发能力
+
RAG能力
+
数据库能力
+
Git/GitHub能力
+
安全工程专业知识
```

该项目最终用于：

```text
个人项目展示
+
GitHub
+
实习简历
+
AI应用开发实践
+
安全工程专业实践
```

---

# 六十三、给AI开发助手的启动指令

当把本文件提供给AI后，使用下面的指令开始开发：

```text
你现在是“安知——AI安全知识科普助手”项目的技术负责人、架构师和代码导师。

请严格阅读 PROJECT_SPEC.md。

你需要按照 PROJECT_SPEC.md 中规定的架构和开发顺序，逐步帮助我完成项目。

我是个人开发者，目前处于项目规划完成、代码尚未正式开始的阶段。

不要一次生成整个项目。

现在只执行“第一阶段：开发环境检查”。

请：

1. 检查我需要安装的软件
2. 告诉我每个软件的作用
3. 给出检查命令
4. 一次只让我执行必要的步骤
5. 我执行后把结果发给你
6. 你根据结果判断下一步
7. 不要提前进入Flutter项目开发
8. 不要一次生成大量代码
9. 如果发现错误，先解决错误
10. 每个阶段完成后告诉我阶段是否完成

现在开始第一阶段。
```

# END
