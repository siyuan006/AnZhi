# 安知 AnZhi — 数据库设计文档

> 版本：V1.0
> 数据库：SQLite（`anzhi.db`）
> ORM：SQLAlchemy
> 来源依据：PROJECT_SPEC.md 第十六、二十三、二十四、三十三节

---

## 1. 设计原则

1. **渐进式建表** —— 不要一次性创建全部表（PROJECT_SPEC 第三十三节）
2. **先核心后扩展** —— 顺序：`User / Category / Knowledge` → `Favorite / History` → `Post / Comment / Like / UserSettings`
3. **字段命名** —— 数据库使用 `snake_case`，Python 模型属性同样使用 `snake_case`
4. **主键** —— 统一使用自增整数 `id`
5. **时间字段** —— 统一 `created_at` / `updated_at`，使用 UTC 时间戳

---

## 2. 实体关系图

```text
                    ┌──────────┐
                    │   User   │
                    └────┬─────┘
        ┌────────────────┼────────────────┬──────────────┐
        │                │                │              │
        ▼                ▼                ▼              ▼
  ┌──────────┐    ┌──────────┐    ┌──────────┐   ┌──────────────┐
  │ Favorite │    │ History  │    │   Post   │   │ UserSettings │
  └────┬─────┘    └────┬─────┘    └────┬─────┘   └──────────────┘
       │               │               │
       ▼               ▼          ┌────┴────┐
  ┌─────────────────────────┐     ▼         ▼
  │       Knowledge         │ ┌────────┐ ┌──────┐
  └────────────┬────────────┘ │Comment │ │ Like │
               │              └────────┘ └──────┘
               ▼
        ┌──────────┐
        │ Category │
        └──────────┘
```

关系摘要：

| 关系 | 类型 | 说明 |
|---|---|---|
| User → Favorite | 1:N | 一个用户有多条收藏 |
| User → History | 1:N | 一个用户有多条浏览记录 |
| User → Post | 1:N | 一个用户发多个帖子 |
| User → UserSettings | 1:1 | 每个用户一份设置 |
| Knowledge → Category | N:1 | 每个知识属于一个分类 |
| Favorite → Knowledge | N:1 | 收藏指向知识 |
| History → Knowledge | N:1 | 历史指向知识 |
| Post → Comment | 1:N | 帖子有多条评论 |
| Post → Like | 1:N | 帖子有多个点赞 |

---

## 3. 表结构定义

### 3.1 `users` —— 用户表

| 字段 | 类型 | 约束 | 说明 |
|---|---|---|---|
| `id` | INTEGER | PK, AUTOINCREMENT | 主键 |
| `username` | VARCHAR(50) | UNIQUE, NOT NULL, INDEX | 用户名 |
| `email` | VARCHAR(120) | UNIQUE, INDEX | 邮箱（可空） |
| `password_hash` | VARCHAR(255) | NOT NULL | 密码哈希，**禁止存明文** |
| `nickname` | VARCHAR(50) | | 昵称 |
| `avatar_url` | VARCHAR(255) | | 头像地址 |
| `study_days` | INTEGER | DEFAULT 0 | 学习天数 |
| `created_at` | DATETIME | DEFAULT now | 创建时间 |
| `updated_at` | DATETIME | | 更新时间 |

> **安全要求：** `password_hash` 使用 bcrypt / argon2，绝不存储或记录明文密码。

---

### 3.2 `categories` —— 分类表

V1.0 固定六个分类，初始化时写入种子数据。

| 字段 | 类型 | 约束 | 说明 |
|---|---|---|---|
| `id` | INTEGER | PK, AUTOINCREMENT | 主键 |
| `name` | VARCHAR(50) | UNIQUE, NOT NULL | 分类名 |
| `slug` | VARCHAR(50) | UNIQUE, NOT NULL | 英文标识，供前端路由使用 |
| `icon` | VARCHAR(50) | | 图标标识 |
| `color` | VARCHAR(20) | | 主题色（十六进制） |
| `description` | VARCHAR(255) | | 分类简介 |
| `sort_order` | INTEGER | DEFAULT 0 | 显示排序 |
| `created_at` | DATETIME | DEFAULT now | 创建时间 |

**种子数据：**

| id | name | slug | 说明 |
|:--:|---|---|---|
| 1 | 消防安全 | `fire` | 火灾预防、灭火器、逃生 |
| 2 | 用电安全 | `electric` | 插座、充电、触电急救 |
| 3 | 交通安全 | `traffic` | 行人、骑行、驾驶 |
| 4 | 校园安全 | `campus` | 宿舍、实验室、欺凌 |
| 5 | 网络与反诈安全 | `cyber` | 诈骗、钓鱼、密码、隐私 |
| 6 | 自然灾害与应急 | `disaster` | 地震、洪水、台风、应急 |

---

### 3.3 `knowledge` —— 知识卡片表

对应 PROJECT_SPEC 第十六节「知识卡片结构」。

| 字段 | 类型 | 约束 | 说明 |
|---|---|---|---|
| `id` | INTEGER | PK, AUTOINCREMENT | 主键 |
| `title` | VARCHAR(200) | NOT NULL, INDEX | 标题 |
| `category_id` | INTEGER | FK → categories.id, INDEX | 所属分类 |
| `summary` | VARCHAR(500) | | 简介 |
| `content` | TEXT | NOT NULL | 正文 |
| `risk_level` | VARCHAR(10) | NOT NULL, DEFAULT 'low' | `low` / `medium` / `high` |
| `image_url` | VARCHAR(255) | | 配图地址 |
| `source` | VARCHAR(500) | | 来源引用 |
| `author` | VARCHAR(50) | | 作者 |
| `view_count` | INTEGER | DEFAULT 0 | 浏览量 |
| `is_published` | BOOLEAN | DEFAULT false | **审核发布开关** |
| `created_at` | DATETIME | DEFAULT now, INDEX | 发布时间 |
| `updated_at` | DATETIME | | 更新时间 |

> **内容安全（PROJECT_SPEC 第十五节）：** 知识卡片流程为 `AI 生成初稿 → 人工审核 → 发布`。
> `is_published` 默认为 `false`，**未经人工审核的内容不得对外可见**。高风险安全知识禁止自动发布。

---

### 3.4 `favorites` —— 收藏表

| 字段 | 类型 | 约束 | 说明 |
|---|---|---|---|
| `id` | INTEGER | PK, AUTOINCREMENT | 主键 |
| `user_id` | INTEGER | FK → users.id, INDEX | 用户 |
| `knowledge_id` | INTEGER | FK → knowledge.id, INDEX | 知识 |
| `created_at` | DATETIME | DEFAULT now | 收藏时间 |

**约束：** `UNIQUE(user_id, knowledge_id)` —— 防止重复收藏。

---

### 3.5 `histories` —— 浏览历史表

| 字段 | 类型 | 约束 | 说明 |
|---|---|---|---|
| `id` | INTEGER | PK, AUTOINCREMENT | 主键 |
| `user_id` | INTEGER | FK → users.id, INDEX | 用户 |
| `knowledge_id` | INTEGER | FK → knowledge.id, INDEX | 知识 |
| `viewed_at` | DATETIME | DEFAULT now, INDEX | 浏览时间 |

**约束：** `UNIQUE(user_id, knowledge_id)`。

> 同一用户重复浏览同一知识时**更新 `viewed_at`**，不新增记录。
> 该 UNIQUE 约束把这条规则固化到数据库层：业务层负责 upsert，
> 即使业务层漏判，数据库也不会产生重复历史。

---

### 3.6 `posts` —— 社区帖子表

| 字段 | 类型 | 约束 | 说明 |
|---|---|---|---|
| `id` | INTEGER | PK, AUTOINCREMENT | 主键 |
| `user_id` | INTEGER | FK → users.id, INDEX | 作者 |
| `title` | VARCHAR(200) | NOT NULL | 标题 |
| `content` | TEXT | NOT NULL | 正文 |
| `category_id` | INTEGER | FK → categories.id | 所属分类（可空） |
| `like_count` | INTEGER | DEFAULT 0 | 点赞数（冗余，便于排序） |
| `comment_count` | INTEGER | DEFAULT 0 | 评论数（冗余） |
| `is_published` | BOOLEAN | DEFAULT true | 是否可见 |
| `created_at` | DATETIME | DEFAULT now, INDEX | 发布时间 |
| `updated_at` | DATETIME | | 更新时间 |

---

### 3.7 `comments` —— 评论表

| 字段 | 类型 | 约束 | 说明 |
|---|---|---|---|
| `id` | INTEGER | PK, AUTOINCREMENT | 主键 |
| `post_id` | INTEGER | FK → posts.id, INDEX | 所属帖子 |
| `user_id` | INTEGER | FK → users.id, INDEX | 评论者 |
| `content` | TEXT | NOT NULL | 评论内容 |
| `parent_id` | INTEGER | FK → comments.id | 父评论（预留二级回复） |
| `created_at` | DATETIME | DEFAULT now | 评论时间 |

---

### 3.8 `likes` —— 点赞表

| 字段 | 类型 | 约束 | 说明 |
|---|---|---|---|
| `id` | INTEGER | PK, AUTOINCREMENT | 主键 |
| `post_id` | INTEGER | FK → posts.id, INDEX | 帖子 |
| `user_id` | INTEGER | FK → users.id, INDEX | 用户 |
| `created_at` | DATETIME | DEFAULT now | 点赞时间 |

**约束：** `UNIQUE(post_id, user_id)` —— 同一用户对同一帖子只能点赞一次。

---

### 3.9 `user_settings` —— 用户设置表

对应 PROJECT_SPEC 第十九节「个性化首页」与第四十二节「个性化」。

| 字段 | 类型 | 约束 | 说明 |
|---|---|---|---|
| `id` | INTEGER | PK, AUTOINCREMENT | 主键 |
| `user_id` | INTEGER | FK → users.id, UNIQUE | 用户（1:1） |
| `followed_categories` | TEXT | DEFAULT '[]' | 关注分类 ID，JSON 数组 |
| `home_modules` | TEXT | DEFAULT '[]' | 首页模块显示配置，JSON |
| `notify_enabled` | BOOLEAN | DEFAULT true | 通知开关 |
| `created_at` | DATETIME | DEFAULT now | 创建时间 |
| `updated_at` | DATETIME | | 更新时间 |

> SQLite 无原生数组类型，`followed_categories` 以 JSON 字符串存储，SQLAlchemy 层负责序列化。

---

## 4. 索引汇总

| 表 | 索引字段 | 目的 |
|---|---|---|
| users | `username` (UNIQUE), `email` (UNIQUE) | 登录查询 |
| knowledge | `category_id`, `created_at`, `risk_level` | 分类筛选、时间排序 |
| favorites | `(user_id, knowledge_id)` UNIQUE | 防重复 + 查询 |
| favorites | `(user_id, created_at)` | 收藏列表按时间排序 |
| histories | `(user_id, knowledge_id)` UNIQUE | 同一知识只保留一条记录 |
| histories | `(user_id, viewed_at)` | 历史列表按时间排序 |
| posts | `created_at`, `user_id` | 帖子列表 |
| likes | `(post_id, user_id)` UNIQUE | 防重复点赞 |

---

## 5. 建表顺序（PROJECT_SPEC 第三十三节）

```text
第 1 批（阶段6-1）✅  User ── Category ── Knowledge
第 2 批（阶段6-2）✅  Favorite ── History
第 3 批（阶段6-3）✅  Post ── Comment ── Like ── UserSettings
```

**不要一次性创建全部表。**

---

## 6. 未来扩展

| 变更 | 阶段 |
|---|---|
| SQLite → PostgreSQL | V1.x |
| 兴趣权重表（`user_interests`，分类权重浮点值） | V2.0 个性化推荐 |
| 向量表 / 外部向量库 | V2.0 RAG |
| 内容审核记录表 | V2.0 AI 社区审核 |

> **变更规则（AI_RULES 第十二节）：** 数据库结构发生重大变化时，
> 必须同步检查 `models` / `schemas` / `API` / Flutter `models` 四处。
