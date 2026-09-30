# 安知 AnZhi — 技术架构文档

> 版本：V1.0
> 依据：PROJECT_SPEC.md 第十二、十三、十四、二十五、二十六、五十一、五十二节

---

## 1. 整体架构

```text
┌──────────────────────────────────────────────┐
│              Flutter Android App             │
│   pages/ · widgets/ · models/ · services/    │
└───────────────────────┬──────────────────────┘
                        │  HTTP / JSON
                        ▼
┌──────────────────────────────────────────────┐
│                 FastAPI 后端                  │
│   api/ · schemas/ · services/ · models/      │
└───────┬───────────────────────────┬──────────┘
        │                           │
        ▼                           ▼
   ┌─────────┐              ┌──────────────┐
   │ SQLite  │              │ AI Service   │
   └─────────┘              └──────┬───────┘
                                   │
                            ┌──────┴──────┐
                            ▼             ▼
                      ┌──────────┐  ┌──────────┐
                      │ DeepSeek │  │   RAG    │
                      │   API    │  │ (V2.0)   │
                      └──────────┘  └──────────┘
```

**关键约束：** DeepSeek API Key 只存在于后端 `.env`，Flutter 端不持有任何第三方密钥。

---

## 2. 后端分层

严格遵循 PROJECT_SPEC 第五十二节与 AI_RULES 第八节，禁止把业务逻辑堆进 `main.py`。

```text
backend/
├── app/
│   ├── main.py              FastAPI 实例、中间件、路由挂载（不含业务逻辑）
│   ├── api/                 路由层：定义 URL 与请求响应，不含业务逻辑
│   ├── schemas/             Pydantic 模型：请求 / 响应数据结构与校验
│   ├── services/            业务逻辑层
│   │   ├── ai/
│   │   │   ├── chat_service.py      调用 DeepSeek（V1.0）
│   │   │   ├── agent_service.py     问题分类（预留）
│   │   │   ├── risk_service.py      风险判断（预留）
│   │   │   ├── rag_service.py       知识检索（预留）
│   │   │   └── safety_guard.py      回答安全审查（预留）
│   │   ├── knowledge/               知识卡片业务逻辑
│   │   ├── community/               社区：帖子 / 评论 / 点赞
│   │   ├── personalization/         个性化设置（关注分类、首页模块）
│   │   └── auth/                    注册、登录、密码与令牌
│   ├── models/              SQLAlchemy 数据库模型
│   ├── database/            连接、会话、初始化
│   └── config/              环境变量读取与配置对象
├── tests/
├── requirements.txt
└── .env.example
```

### 各层职责边界

| 层 | 做 | 不做 |
|---|---|---|
| `api/` | 解析请求、调用 service、返回响应 | 写业务规则、直接操作数据库 |
| `schemas/` | 数据结构定义与字段校验 | 访问数据库、调用外部 API |
| `services/` | 业务规则、编排、外部调用 | 感知 HTTP 细节 |
| `models/` | 表结构定义与关系 | 业务判断 |

**调用方向是单向的：** `api → services → models`，不允许反向依赖。

---

## 3. 前端分层

严格遵循 PROJECT_SPEC 第五十一节与 AI_RULES 第七节。

```text
frontend/lib/
├── main.dart        入口，仅调用 runApp
├── app.dart         MaterialApp、主题、路由装配
├── core/            主题、常量（不属于任何业务模块的全局配置）
├── models/          数据模型，与后端 schemas 对应
├── services/        网络请求（阶段 7 加入）
├── pages/           页面，一个页面一个文件
├── widgets/         可复用组件
└── utils/           工具函数
```

### 当前文件

| 文件 | 职责 |
|---|---|
| `main.dart` | 入口 |
| `app.dart` | 根组件：主题 + 首页装配 |
| `core/app_constants.dart` | 六大分类、三级风险、首页模块标识 |
| `core/app_theme.dart` | Material 3 主题与配色 |
| `core/relative_time.dart` | 后端 naive UTC 时间戳的解析与相对时间显示 |
| `models/knowledge_item.dart` | 知识卡片模型 |
| `models/ai_answer.dart` | AI 结构化回答模型 + 聊天消息模型 |
| `widgets/main_scaffold.dart` | 底部导航主框架 |
| `widgets/risk_badge.dart` | 风险等级标签 |
| `widgets/section_header.dart` | 区块标题 |
| `widgets/knowledge_tile.dart` | 知识卡片列表项 |
| `widgets/category_grid.dart` | 分类网格 |
| `pages/home_page.dart` | 首页 |
| `pages/ai_page.dart` | AI 问答 |
| `pages/knowledge_page.dart` | 知识 |
| `pages/community_page.dart` | 社区 |
| `pages/profile_page.dart` | 我的 |

---

## 4. AI 服务演进路线（渐进式，禁止一步到位）

### V1.0

```text
用户问题 → FastAPI → ChatService → DeepSeek → 返回
```

### V1.5

```text
用户问题 → 安全知识库检索 → DeepSeek → 返回（带来源）
```

### V2.0

```text
用户问题
   ↓
AgentService      问题分类
   ↓
RiskService       风险判断（low / medium / high）
   ↓
RAGService        知识库检索
   ↓
DeepSeek          生成回答
   ↓
SafetyGuard       安全审查
   ↓
结构化回答 + 来源引用
```

**V1.0 只实现 ChatService。** 其余模块在 `services/ai/` 下预留文件与接口签名，
但不实现具体逻辑 —— 预留结构不等于虚假实现，未实现的模块必须明确标注。

---

## 5. 风险等级与回答策略

三级风险系统（PROJECT_SPEC 第十节）直接决定回答的组织方式：

| 等级 | 触发场景 | 回答策略 |
|:--:|---|---|
| 🟢 LOW | 普通科普（「灭火器有哪些种类？」） | 正常科普，可展开解释 |
| 🟡 MEDIUM | 潜在风险（「插座冒烟怎么办？」） | 强调停止操作，给出安全建议 |
| 🔴 HIGH | 紧急情况（「家里着火怎么办？」） | **简洁**、优先立即措施、不提供危险操作、建议联系专业救援、**不做长篇科普** |

**AI 安全原则优先序（第十一节）：**

```text
生命安全优先 → 避免危险操作 → 给出可执行步骤
→ 必要时建议寻求专业帮助 → 最后进行知识解释
```

**高风险禁止：** 鼓励进入危险区域、提供危险实验步骤、对紧急情况娱乐化、信息不足时过度确定。

---

## 6. 数据流示例：AI 问答（V1.0 目标形态）

```text
① Flutter  AiPage 用户输入
        ↓
② services/ api_client.dart   POST /api/chat  {"message": "..."}
        ↓
③ FastAPI  api/chat.py        解析请求 → 调用 ChatService
        ↓
④ schemas 校验 message 非空且 ≤1000 字符
        ↓
⑤ services/ai/chat_service.py
        ↓
⑥ config 读取 .env 中的 DEEPSEEK_API_KEY
        ↓
⑦ DeepSeek API 返回
        ↓
⑧ SafetyGuard 审查（阶段 9 接入）
        ↓
⑨ 组装为 AiAnswer 结构返回
        ↓
⑩ Flutter  models/ai_answer.dart 解析 → widgets 渲染
```

---

## 7. 配置与安全

### 环境变量流转

```text
.env（仅后端本地，永不提交）
   ↓
config/ 读取为配置对象
   ↓
services/ 使用
```

### 安全红线（PROJECT_SPEC 第四十六节、AI_RULES 第九节）

| 禁止 | 已采取的防护 |
|---|---|
| API Key 写入 Flutter | 客户端不持有任何第三方密钥 |
| API Key 提交 GitHub | `.gitignore` 忽略 `.env`（已实测 `git add .env` 被拒） |
| API Key 写入 README | 仓库只提供 `.env.example` 空模板 |
| API Key 硬编码 | 统一经 `config/` 从环境变量读取 |

---

## 8. 未来扩展点

| 扩展 | 预留位置 | 阶段 |
|---|---|---|
| RAG 向量检索 | `services/ai/rag_service.py` | V2.0 |
| 风险判断 Agent | `services/ai/risk_service.py` | V2.0 |
| SSE 流式回答 | `api/chat.py` 新增 `/api/chat/stream` | V2.0 |
| PostgreSQL | `database/` 换连接串 | V1.x |
| AI 社区审核 | `services/ai/` 新增审核服务 | V2.0 |

**变更规则（AI_RULES 第五、十二节）：** 技术栈变更或数据库结构重大变化时，
必须先说明原因与影响范围，等待确认后再执行。
