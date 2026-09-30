# 安知 AnZhi — AI 安全知识科普助手

> 基于 **Flutter + FastAPI + DeepSeek + RAG** 的 AI 安全知识科普 Android 应用

> 检索用的是关键词加权匹配（不是 Embedding 向量检索，原因见下方「RAG 为什么不是 Embedding + 向量库」）。

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
| 8 | 接入 DeepSeek | 🟡 代码已完成，缺 API Key |
| 9 | AI 安全控制（SafetyGuard） | ✅ 已完成 |
| 10 | 知识系统 | ✅ 已完成 |
| 11 | 收藏 / 历史记录 | ✅ 已完成 |
| 12 | 社区 | ✅ 已完成（列表 / 详情 / 评论 / 点赞 / 发帖 / 我的帖子 / 删帖） |
| 13 | 个性化 | ✅ 已完成（关注领域 / 首页布局 / 通知设置 / 首页按设置显示与推荐） |
| 14 | RAG | ✅ 已完成（知识库检索引用；关键词匹配而非语义检索，原因见下） |
| 15 | 测试 | ⬜ 待开始 |
| 16 | UI 优化 | ⬜ 待开始 |
| 17 | APK 打包 | ⬜ 待开始 |
| 18 | GitHub 发布 | ⬜ 待开始 |

**当前进度：Flutter 前端 + FastAPI 后端 + SQLite 数据库（9 张表）+ 前后端 HTTP 打通 + AI 问答链路 + 安全审查 + 知识库检索引用 + 知识详情与浏览计数 + 登录注册 + 收藏 + 浏览历史 + 完整的社区互动（浏览 / 评论 / 点赞 / 发帖 / 删帖）+ 个性化（关注领域 / 首页布局 / 通知设置）。**

- 前端：可编译、可运行，已产出 debug APK；首页、知识页、知识详情页、AI 问答页、登录注册页、我的收藏页、浏览历史页、社区页、帖子详情页、发帖页、我的帖子页、我的页、关注领域页、首页布局页、通知设置页**均已改为调用真实接口**，按需显示加载 / 失败 / 空状态。AI 回答里的「相关知识」可一路点进知识详情页读原文
- 后端：`uvicorn app.main:app` 可启动，`/`、`/api/health`、`/api/categories`、`/api/knowledge`、`/api/knowledge/{id}`、`/api/knowledge/{id}/view`、`/api/chat`、`/api/auth/*`、`/api/favorites`、`/api/history`、`/api/posts`、`/api/posts/mine`、`/api/posts/{id}/comments`、`/api/posts/{id}/like`、`/api/settings` 已实测返回正确响应
- 数据库：`backend/anzhi.db` 已建全部 9 张表，六大分类种子数据已写入
- 联调：前端 363 个测试 + 后端 540 个测试全部通过；另有 70 个「真实后端」集成测试（默认跳过；开启后 43 通过 / 27 如实跳过，跳过的是依赖「知识库已发布内容」与「已配置 API Key」的那几组，而非空跑）

尚未打通的部分（按阶段推进，不做假实现）：

| 未完成项 | 现状 | 计划阶段 |
|---|---|---|
| **DeepSeek API Key** | 仓库里没有、也不应该有 Key。`/api/chat` 因此返回 **503 + 中文说明**（而非 500），`/api/health` 返回 `ai_service: "not_configured"`。**AI 问答尚未端到端跑通** | 配置 Key 即可 |
| **JWT_SECRET** | 未配置时开发环境每次启动随机生成，**后端一重启所有登录状态失效**；生产环境缺此项会拒绝启动 | 配置 `.env` 即可 |
| 内容发布状态 | 12 条初稿已入库但**均为「待审核」**：`/api/knowledge` 因此如实返回空，App 首页与知识页显示「暂无内容」 | 待人工审核 |
| **登录状态不持久化** | App 关闭后需要重新登录。持久化需要一个存储插件（如 `shared_preferences`），属新增第三方依赖，按 AI_RULES 第五节**未擅自引入** | 待确认后接入 |
| **通知开关目前不生效** | V1.0 没有推送功能。开关会如实存下偏好，但页面上**明说「V1.0 还没有通知推送功能」**，不做一个看起来在生效的开关 | 后续版本 |
| 社区里的搜索 | 搜索帖子尚未实现，按钮点了会**如实标注「后续版本」**而不是没反应 | 后续版本 |
| 社区里的私信 / 关注 | V1.0 明确不做（PROJECT_SPEC 第二十节） | 不做 |
| `GET /api/home` 首页聚合接口 | 首页改为分别调用 `/api/knowledge`、`/api/posts`、`/api/settings` 三个接口 | 后续版本 |
| **知识检索是关键词匹配，不是语义检索** | 问法里出现知识库用过的词才检索得到，换个说法就检索不到。真正的语义检索要 Embedding + 向量库，DeepSeek 没有 Embedding 接口，引入第三方属**更换技术栈**（AI_RULES 第五节），未擅自引入 | 待确认后接入 |

> **关于「关注领域 / 首页布局有什么效果」：** 两个开关都真的接到了首页上，
> 不是只存一个偏好值：
> - **首页布局**：关掉的模块不再渲染。五个全关掉时首页会说明「是你自己在
>   首页布局里关掉的」，并给一条回去打开的路，而不是留一片空白
> - **关注领域**：关注的分类通过 `GET /api/knowledge?prefer_categories=…`
>   排到「推荐知识」前面。这是**排序偏好而不是筛选** ——
>   关注消防不等于看不到别的领域，返回条数也不变
>
> 未登录时首页不发设置请求（没有账号可谈，发出去只会拿到 401），
> 设置拉不到时按默认布局显示：首页的主体是安全知识，
> 设置只是调整它的摆法，不该因为一次设置请求失败就变成错误页。

> **关于「AI 问答还不能用」：** 阶段 8 完成的是**链路代码**——
> 用户输入 → `POST /api/chat` → FastAPI → `ChatService` → DeepSeek → 结构化回答 → Flutter 渲染。
> 这条链路的每一段都有测试覆盖，**唯一没有验证过的是 DeepSeek 本身**：
> 没有 Key 就无法发一次真实请求。在 `.env` 里配置 `DEEPSEEK_API_KEY` 之后，
> 需要重新跑一次下面这条命令来确认它真的通了（配置前它会如实报告 503）：
>
> ```bash
> cd frontend
> flutter test test/integration/live_backend_test.dart --dart-define=ANZHI_LIVE_BACKEND=true
> ```
>
> 该测试在检测到 Key 已配置时会自动从「验证 503」切换为「验证真实回答可被解析」，
> 并额外验证**每条 `references` 都能按 id 读回原文**（阶段 14）。
> 未配置时这几条会如实标记为 skipped，而不是假装通过。

> **关于「首页是空的」：** 这不是故障。知识内容遵循
> `AI 生成初稿 → 人工审核 → 发布`（PROJECT_SPEC 第十五节），
> 未发布的内容在接口层一律视为不存在。审核并发布后，
> App 无需任何改动即可显示内容（见下方「知识内容审核流程」）。

> **关于「RAG 为什么不是 Embedding + 向量库」：** PROJECT_SPEC 第十四节把
> 向量检索放在 V2.0，第四十三节要求 Embedding 模型 + 向量数据库；
> 而 DeepSeek **没有 Embedding 接口**，接第三方 Embedding 服务或换模型
> 都属于更换技术栈（AI_RULES 第五节、第五十五节要求先说明理由并等待确认），
> 因此本阶段实现的是第十四节 V1.5 的**知识检索**：在现有的
> `knowledge` 表上做中文关键词加权匹配（二元切分，标题 6 / 摘要 3 / 正文 1），
> 只检索 `is_published` 为真的卡片，把命中的卡片作为 `references` 返回。
>
> 它带来的东西是真的：用户拿到的每条引用都能按 id 读回原文，
> 而不是模型自己写的一串无法核实的书名。局限也是真的：
> **问法里不含知识库用过的词就检索不到**（详见上表）。
> 将来替换成向量检索时接口形状不用变，客户端不需要改动。

---

## 核心功能

| 功能 | 说明 |
|---|---|
| 🤖 **AI 安全问答** | 提问安全问题，AI 返回结构化回答 |
| ⚠️ **三级风险系统** | 🟢 LOW / 🟡 MEDIUM / 🔴 HIGH，高风险问题优先给出应急处置 |
| 📚 **安全知识卡片** | 六大分类的结构化科普内容 |
| ⭐ **收藏与历史** | 收藏知识、自动记录浏览历史 |
| 👥 **社区** | 帖子、评论、点赞、发帖与删帖 |
| 🎯 **个性化首页** | 关注分类、自定义显示模块 |
| 🔍 **知识库引用** | 回答带本项目已发布卡片的引用，可点开读原文（当前为关键词检索，非语义检索） |

---

## 技术栈

| 层 | 技术 |
|---|---|
| 前端 | Flutter / Dart |
| 后端 | Python / FastAPI |
| 数据库 | SQLite（V1.0）→ PostgreSQL |
| AI | DeepSeek API |
| 知识检索 | 关键词加权匹配（V1）；Embedding + 向量数据库属 V2.0，需先确认技术栈 |
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
     DeepSeek   RAGService（关键词检索）
```

**AI 服务模块（渐进式实现）：**

```text
V1.0   ChatService ──→ DeepSeek ──→ 返回

V1.5   ChatService
          ↓
       RAGService      知识检索（当前：关键词加权匹配）
          ↓
       DeepSeek
          ↓
       SafetyGuard     安全审查
          ↓
       最终回答 + references（可点开的原文）

V2.0   RiskService     风险判断（独立成层）
       RAGService      语义检索（Embedding + 向量库，需先确认技术栈）
```

---

## 目录结构

```text
AnZhi/
├── frontend/          Flutter 项目
│   ├── lib/
│   │   ├── services/  网络请求（api_client / knowledge_api / chat_api / auth_api / favorite_api / history_api / post_api / settings_api）
│   │   ├── pages/     五大页面 + 知识详情页 + 登录注册页 + 我的收藏页 + 浏览历史页 + 帖子详情页 + 个性化设置三页
│   │   ├── widgets/   通用组件
│   │   ├── models/    数据模型
│   │   └── core/      主题、常量、登录状态（auth_controller）、时间解析（relative_time）
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
│   │   │   ├── ai/    deepseek_client / chat_service / prompts / errors /
│   │   │   │          safety_guard / rag_service（知识检索）
│   │   │   ├── knowledge/  knowledge_service（列表 / 详情 / 浏览计数）/ favorite_service / history_service
│   │   │   ├── community/  post_service（列表 / 详情 / 摘要截断）/ comment_service
│   │   │   └── auth/   passwords（口令哈希）/ tokens（JWT）/ auth_service
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
  "references": [
    {
      "id": 3,
      "title": "宿舍发生火灾如何正确逃生",
      "summary": "低姿撤离、不乘电梯、不贪恋财物。",
      "category_id": 1,
      "risk_level": "high"
    }
  ],
  "warning": "......"
}
```

**`sources` 与 `references` 是两种东西，界面上也分两栏显示：**

| | `sources`（参考来源） | `references`（相关知识） |
|---|---|---|
| 谁写的 | **模型自己写的** | 后端从知识库查出来的 |
| 能否核实 | 不能。模型可能写错，甚至编出一条不存在的标准 | 能。每条都带 id，点开就是知识库里的原文 |
| 为空时 | 正常 | 正常（知识库没有相关内容，界面上整栏不显示） |

> 混成一个列表会让用户以为「模型说的」也有据可查。分开展示，
> 用户至少知道哪一条是能点开验证的。

**安全原则：** 生命安全优先 → 避免危险操作 → 给出可执行步骤 → 必要时建议寻求专业帮助 → 最后进行知识解释。

### 回答为什么要经过 SafetyGuard

**模型不保证听话。** 提示词能降低出问题的概率，但消除不了它 ——
把安全性完全寄托在提示词上是不负责的做法。所以在模型输出与用户之间，
还有一层确定性审查（`backend/app/services/ai/safety_guard.py`）：

```text
用户问题 → ChatService → DeepSeek → 规范化 → SafetyGuard → 最终回答
```

| 能力 | 行为 |
|---|---|
| **危险操作拦截** | 命中即整条替换为兜底话术，步骤与 `sources` 一并清空，风险等级强制为 `high`。**知识库 `references` 不清空** |
| **风险等级只抬不降** | 问题含「触电了」「闻到燃气味」等正在发生的危险 → 至少 `high`。**任何情况下都不降级** |
| **警告补齐** | 中高风险缺警告时补通用提示；紧急场景的警告若不含求助电话，追加提示 |
| **不编造** | 高风险回答缺步骤时**只记录不补** —— 编造一条「看起来专业」的操作建议，比明说「请听从专业人员指挥」危险得多 |

审查层**不调用第二次大模型**：那只是把「模型可能出错」的概率叠了两次，
而且会让「这条回答为什么被拦下」变得不可复现、不可测试。

> **否定判定是这个模块最关键的一处设计。**
> 提示词要求模型说明「什么不要做」，所以正确的回答里必然包含危险短语本身 ——
> 「切勿返回火场取物」里就有「返回火场」四个字。
> 用子串匹配直接拦，会把**最该保留的回答**全部误杀。
> 因此危险短语先在**小句内**做否定判定：同一个小句里出现
> 「不要 / 切勿 / 严禁」即视为劝阻，放行；
> 而「不要犹豫，立即返回火场取物」仍会被拦下（否定词在前一个小句，不算数）。

**它拦不住什么：** 这是规则，不是判断力。它能拦住已知的危险表述，
拦不住它没被教过的说法。所以只能说「已知的危险做法不会原样送到用户面前」，
**不能说「AI 输出已经安全」**。

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
flutter test           # 运行测试（316 passed，另有 59 个真实后端测试默认跳过）
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
.venv\Scripts\python.exe -m pytest      # 415 passed
```

### API 配置

```bash
cd backend
cp .env.example .env
# 编辑 .env，填入 DEEPSEEK_API_KEY
```

> `.env` 不存在时后端**仍可正常启动**，健康检查会如实报告
> `ai_service: "not_configured"`，不会崩溃也不会伪造状态。
>
> 未配置 Key 时 `POST /api/chat` 返回 **503** 与一句可直接展示的中文说明
> （`AI 服务未配置，请联系管理员在后端 .env 中设置 DEEPSEEK_API_KEY`），
> 而不是 500 或一句含糊的「服务异常」——「部署没配好」不是程序崩溃，
> 用户看到 500 只会以为 App 坏了。
>
> **API Key 只存在于后端的 `.env` 中**（PROJECT_SPEC 第三十五节）：
> 不写进 Flutter 代码、不提交 GitHub、不写入 README、不硬编码。
> `.env` 已在 `.gitignore` 中。

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
| 假后端 | `flutter test` | 316 个测试，无需后端，验证页面在成功 / 失败 / 空数据下的表现 |
| 真实后端 | 见下 | 59 个测试，验证后端真实返回的字段能被客户端正确解析 |

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

- [x] 知识库检索 + 来源引用（关键词匹配，见上）
- [ ] 语义检索（Embedding + 向量数据库）—— 属更换技术栈，需先确认
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
