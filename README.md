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
| 5 | FastAPI 后端 | ⬜ 待开始 |
| 6 | SQLite 数据库 | ⬜ 待开始 |
| 7 | 前后端通信 | ⬜ 待开始 |
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

**当前进度：Flutter 前端骨架完成。** App 可编译、可运行，已产出 debug APK。
AI 问答尚未接入后端（阶段 8），数据来自临时占位文件 `lib/core/sample_data.dart`。

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
├── backend/           FastAPI 后端
│   ├── app/
│   │   ├── main.py
│   │   ├── api/       路由
│   │   ├── models/    数据库模型
│   │   ├── schemas/   请求/响应结构
│   │   ├── services/  业务逻辑
│   │   │   └── ai/    chat / risk / rag / safety_guard
│   │   ├── database/  数据库连接
│   │   └── config/    环境配置
│   ├── tests/
│   ├── requirements.txt
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
flutter test           # 运行测试
flutter run            # 连接真机/模拟器运行
flutter build apk --debug    # 构建 APK
```

产物路径：`frontend/build/app/outputs/flutter-apk/app-debug.apk`

### 后端（阶段 5 完成后可用）

```bash
cd backend
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
uvicorn app.main:app --reload
```

### API 配置

```bash
cd backend
cp .env.example .env
# 编辑 .env，填入 DEEPSEEK_API_KEY
```

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
