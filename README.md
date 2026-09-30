# 安知 AnZhi — AI 安全知识科普助手

> 基于 **Flutter + FastAPI + DeepSeek + RAG** 的 AI 安全知识科普 Android 应用

面向普通用户和大学生的安全知识科普 App。通过 AI 问答、安全知识卡片、个性化推荐与社区交流，帮助用户学习消防、用电、交通、校园、网络反诈、自然灾害六大领域的安全知识。

---

## 项目状态

> 本表随开发进度实时更新，**只标记真实完成并通过测试的内容**。

| 阶段 | 内容 | 状态 |
|:---:|---|:---:|
| 1 | 开发环境配置 | ✅ 已完成 |
| 2 | Git 仓库初始化 | ✅ 已完成 |
| 3 | Flutter 项目创建 | ✅ 已完成 |
| 4 | Flutter 五大页面 + 底部导航 | ✅ 已完成 |
| 5 | FastAPI 后端 | ✅ 已完成 |
| 6 | SQLite 数据库 | ✅ 已完成 |
| 7 | 前后端通信 | ✅ 已完成 |
| 8 | 接入 DeepSeek | ⬜ 待开始 |
| 9 | AI 安全控制（SafetyGuard） | ⬜ 待开始 |
| 10 | 知识系统 | ⬜ 待开始 |
| 11 | 收藏 / 历史记录 | ⬜ 待开始 |
| 12 | 社区 | ⬜ 待开始 |
| 13 | 个性化 | ⬜ 待开始 |
| 14 | RAG | ⬜ 待开始 |
| 15 | 测试 | ⬜ 待开始 |
| 16 | UI 优化 | ⬜ 待开始 |
| 17 | APK 打包 | ⬜ 待开始 |
| 18 | GitHub 发布 | ⬜ 待开始 |

**当前进度：Flutter 前端 + FastAPI 后端 + SQLite 数据库（9 张表）+ 前后端 HTTP 打通。**

- 前端：可编译、可运行，已产出 debug APK；知识页与首页的知识模块**已改为调用真实接口**，按需显示加载 / 失败 / 空状态
- 后端：`uvicorn app.main:app` 可启动，`/`、`/api/health`、`/api/categories`、`/api/knowledge` 已实测返回正确响应
- 数据库：`backend/anzhi.db` 已建全部 9 张表，六大分类种子数据已写入
- 联调：前端 50 个测试 + 后端 96 个测试全部通过；另有 8 个「真实后端」集成测试跑通

尚未打通的部分（按阶段推进，不做假实现）：

| 未完成项 | 现状 | 计划阶段 |
|---|---|---|
| 内容发布状态 | 12 条初稿已入库但**均为「待审核」**：`/api/knowledge` 因此如实返回空，App 首页与知识页显示「暂无内容」 | 待人工审核 |
| 社区帖子 | 仍为占位数据 `lib/core/sample_data.dart`（知识部分的占位数据已删除） | 12 |
| 知识详情页 | 接口已就绪，页面点击后仍提示「阶段 10 实现」 | 10 |
| `GET /api/home` 首页聚合接口 | 首页改为直接调用 `/api/knowledge` 取前 5 条 | 13 |
| DeepSeek AI 问答 | `/api/health` 返回 `ai_service: "not_configured"` | 8 |

> **关于「首页是空的」：** 这不是故障。知识内容遵循
> `AI 生成初稿 → 人工审核 → 发布`（PROJECT_SPEC 第十五节），
> 未发布的内容在接口层一律视为不存在。审核并发布后，
> App 无需任何改动即可显示内容（见下方「知识内容审核流程」）。

---

## 核心功能

| 功能 | 说明 |
|---|---|
| 🤖 **AI 安全问答** | 提问安全问题，AI 返回结构化回答 |
| ⚠️ **三级风险系统** | 🟢 LOW / 🟡 MEDIUM / 🔴 HIGH，高风险问题优先给出应急处置 |
| 📚 **安全知识卡片** | 六大分类的结构化科普内容 |
| ⭐ **收藏与历史** | 收藏知识、自动记录浏览历史 |
| 👥 **社区** | 帖子、评论、点赞 |
| 🎯 **个性化首页** | 关注分类、自定义显示模块 |
| 🔍 **RAG 检索增强** | 基于安全知识库的引用来源回答（V2.0） |

---

## 技术栈

| 层 | 技术 |
|---|---|
| 前端 | Flutter / Dart |
| 后端 | Python / FastAPI |
| 数据库 | SQLite（V1.0）→ PostgreSQL |
| AI | DeepSeek API |
| RAG | Embedding + 向量数据库（V2.0） |
| 版本管理 | Git / GitHub |

---

## 项目架构

```text
Flutter (Android App)
        │
        │ HTTP / JSON
        ▼
   FastAPI 后端
        │
   ┌────┴────┐
   │         │
SQLite   AI Service
              │
        ┌─────┴─────┐
        │           │
    DeepSeek       RAG (V2.0)
```

**AI 服务模块规划（渐进式实现）：**

```text
V1.0   ChatService ──→ DeepSeek ──→ 返回

V2.0   ChatService
          ↓
       RiskService     风险判断
          ↓
       RAGService      知识检索
          ↓
       DeepSeek
          ↓
       SafetyGuard     安全审查
          ↓
       最终回答 + 来源引用
```

---

## 目录结构

```text
AnZhi/
├── frontend/          Flutter 项目
│   ├── lib/
│   │   ├── services/  网络请求（api_client / knowledge_api）
│   │   ├── pages/     五大页面
│   │   ├── widgets/   通用组件
│   │   ├── models/    数据模型
│   │   └── core/      主题、常量、占位数据
│   └── test/
│       ├── helpers/     假后端（MockClient）
│       ├── services/    接口层测试
│       ├── pages/       页面测试
│       └── integration/ 真实后端连通性测试（默认跳过）
├── backend/           FastAPI 后端
│   ├── app/
│   │   ├── main.py
│   │   ├── api/       路由
│   │   ├── models/    数据库模型
│   │   ├── schemas/   请求/响应结构
│   │   ├── services/  业务逻辑
│   │   │   └── ai/    chat / risk / rag / safety_guard
│   │   ├── database/  数据库连接、种子数据、内容审核工具
│   │   └── config/    环境配置
│   ├── tests/
│   ├── requirements.txt
│   ├── pytest.ini
│   └── .env.example
├── docs/              PRD / 架构 / API / 数据库文档
├── assets/            图片等静态资源
├── .gitignore
├── README.md
└── PROJECT_SPEC.md
```

---

## AI 回答结构

AI 回答不是纯文本，而是结构化 JSON：

```json
{
  "question": "宿舍发生火灾怎么办？",
  "category": "消防安全",
  "risk_level": "high",
  "answer": "......",
  "steps": ["......", "......"],
  "sources": ["......"],
  "warning": "......"
}
```

**安全原则：** 生命安全优先 → 避免危险操作 → 给出可执行步骤 → 必要时建议寻求专业帮助 → 最后进行知识解释。

---

## 安全说明

本项目对 API Key 采取**严格隔离**：

```text
Flutter  ──→  FastAPI  ──→  .env  ──→  DeepSeek API
                              ↑
                    永不进入代码仓库
```

- ✅ `.env` 已加入 `.gitignore`（已实测验证 `git add .env` 被拒绝）
- ✅ 仓库仅提供 `.env.example` 模板
- ✅ API Key 只存在于后端服务器，Flutter 端不持有任何密钥

---

## 环境要求

| 工具 | 版本 | 说明 |
|---|---|---|
| Flutter | 3.47.5 | 含 Dart 3.13.4 |
| Python | 3.12.10 | FastAPI 后端 |
| Git | 2.54.0 | 版本管理 |
| JDK | 17+ | Android 构建（实测 22.0.2 可用） |
| Android SDK | API 36 + build-tools 36.0.0 | 经 cmdline-tools 安装 |
| Android NDK | 28.2.13676358 | Flutter 模板默认要求 |

> 本项目使用 **Android 命令行工具** 而非 Android Studio 完成 SDK 安装：
> 体积更小、可脚本化，对构建 APK 完全够用。
> 需要图形化模拟器或 IDE 时可另行安装 Android Studio。

### 国内网络环境说明

在部分网络环境下，直连 `services.gradle.org` / `plugins.gradle.org` / Maven Central
会出现 TLS 握手被中断，导致构建失败。本项目已做两处适配：

1. `frontend/android/settings.gradle.kts` 与 `build.gradle.kts` 中优先使用阿里云镜像
2. 用户级 `~/.gradle/gradle.properties` 可配置本地代理（该文件不在仓库内）

---

## 运行方法

### 前端（已验证可用）

```bash
cd frontend
flutter pub get
flutter analyze        # 静态检查
flutter test           # 运行测试（50 passed）
flutter run            # 连接真机/模拟器运行
flutter build apk --debug    # 构建 APK
```

产物路径：`frontend/build/app/outputs/flutter-apk/app-debug.apk`

**后端地址：** App 默认连接 `http://10.0.2.2:8000`（Android 模拟器访问宿主机的固定地址），
开箱即用。真机调试时后端在电脑上，需显式指定电脑的局域网 IP：

```bash
flutter run --dart-define=ANZHI_API_BASE_URL=http://192.168.1.5:8000
```

> 配置集中在 `lib/services/api_client.dart` 的 `ApiConfig`，
> **不要把地址硬编码到页面里**。
> Android 9 起默认禁止明文 HTTP，明文放行规则在
> `android/app/src/main/res/xml/network_security_config.xml`：
> 正式包只放行本机回环地址，debug 包才整体放行（见 `src/debug/`）。

### 后端（已验证可用）

```bash
cd backend
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt

# 初始化数据库（建表 + 写入六大分类，可重复执行）
.venv\Scripts\python.exe -m app.database.init_db

uvicorn app.main:app --reload
```

启动后：

| 地址 | 说明 |
|---|---|
| http://127.0.0.1:8000/ | 服务存活检查 |
| http://127.0.0.1:8000/api/health | 健康检查（含数据库 / AI 配置状态） |
| http://127.0.0.1:8000/docs | Swagger 交互式文档 |

运行测试：

```bash
cd backend
.venv\Scripts\python.exe -m pytest      # 96 passed
```

### API 配置

```bash
cd backend
cp .env.example .env
# 编辑 .env，填入 DEEPSEEK_API_KEY
```

> `.env` 不存在时后端**仍可正常启动**，健康检查会如实报告
> `ai_service: "not_configured"`，不会崩溃也不会伪造状态。

### 知识内容审核流程

知识卡片遵循 `AI 生成初稿 → 人工审核 → 发布`（PROJECT_SPEC 第十五节）。
初稿默认**不发布**，因此刚建库时 `GET /api/knowledge` 会如实返回空列表。

```bash
cd backend

# 1. 导入初稿（12 条，全部为「待审核」状态）
.venv\Scripts\python.exe -m app.database.review --import-drafts

# 2. 查看待审核内容
.venv\Scripts\python.exe -m app.database.review --list-pending

# 3. 逐条审核后发布（补充 source 权威出处后再发布更稳妥）
.venv\Scripts\python.exe -m app.database.review --publish 1,2,3

# 4. 发现问题时撤回
.venv\Scripts\python.exe -m app.database.review --unpublish 2
```

> 未发布的内容在接口层一律视为不存在（详情接口返回 404 而非 403），
> 因此不会出现「能看到标题但打不开」的情况。

### 前后端联调

```text
Flutter 页面
    │  只负责渲染与交互
    ▼
lib/services/         ← 网络层：超时、错误翻译、地址配置
    │  HTTP / JSON
    ▼
FastAPI app/api/      ← 只解析参数、调用 service、包装响应
    │
app/services/         ← 业务规则（谁能看见什么、按什么排序）
    │
app/models/           ← 表结构
```

分层是单向的：页面不碰 HTTP，路由不写业务规则。

联调相关的测试分两层：

| 层次 | 命令 | 说明 |
|---|---|---|
| 假后端 | `flutter test` | 50 个测试，无需后端，验证页面在成功 / 失败 / 空数据下的表现 |
| 真实后端 | 见下 | 8 个测试，验证后端真实返回的字段能被客户端正确解析 |

```bash
# 终端 1：启动后端
cd backend
.venv\Scripts\python.exe -m uvicorn app.main:app --port 8000

# 终端 2：对着真实后端跑集成测试
cd frontend
flutter test test/integration/live_backend_test.dart --dart-define=ANZHI_LIVE_BACKEND=true
```

> 集成测试**默认跳过**，不会混进 `flutter test` 的结果里假装通过。
> 它存在的意义是拦截「字段名漂移」这类问题 ——
> 假后端是照着客户端的预期写的，永远发现不了前后端字段对不上的情况。
>
> 注意：`flutter test` 环境会拦截真实网络请求，
> 因此页面级测试只能配假后端，真实连通性验证在网络层完成。

---

## 开发规范

- **提交前缀：** `feat:` `fix:` `refactor:` `docs:` `test:` `chore:`
- **开发节奏：** 小步开发 → 运行测试 → 确认正确 → Git 提交 → 继续下一步
- **禁止：** 未经测试宣布完成、伪造接口或测试结果

---

## 未来规划

- [ ] RAG 检索增强生成 + 来源引用
- [ ] AI 个性化推荐（兴趣标签加权）
- [ ] AI 社区内容审核
- [ ] 危险化学品、生产安全、职业安全等扩展分类
- [ ] PostgreSQL 迁移
- [ ] iOS 支持

---

## 截图

> 待 UI 完成后补充。

---

## 文档

| 文档 | 说明 |
|---|---|
| [PROJECT_SPEC.md](PROJECT_SPEC.md) | 项目总规格（架构、阶段、规范） |
| [AI_RULES.md](AI_RULES.md) | AI 开发助手规则 |
| [docs/PRD.md](docs/PRD.md) | 产品需求文档 |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | 技术架构 |
| [docs/API.md](docs/API.md) | 接口文档 |
| [docs/DATABASE.md](docs/DATABASE.md) | 数据库设计 |

---

## 开发背景

个人项目，结合安全工程专业知识与 AI 应用开发实践。目标不是制作演示 Demo，而是产出一个结构合理、能够运行、可展示的完整 AI 应用。

## License

待定
