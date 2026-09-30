# 安知 AnZhi — API 接口文档

> 版本：V1.0
> 基础地址：`http://127.0.0.1:8000`
> 数据格式：`application/json`
> 交互式文档：启动后端后访问 `/docs`（Swagger UI）
> 依据：PROJECT_SPEC.md 第三十二、三十四、三十六、三十八 ~ 四十二节

---

## 1. 通用约定

### 1.1 响应格式

**成功：** 直接返回业务数据（HTTP 200 / 201）

**失败：** 统一错误结构

```json
{
  "detail": "错误说明"
}
```

### 1.2 状态码

| 状态码 | 含义 |
|:--:|---|
| 200 | 成功 |
| 201 | 创建成功 |
| 400 | 请求参数错误 |
| 401 | 未认证 |
| 403 | 无权限 |
| 404 | 资源不存在 |
| 422 | 参数校验失败（FastAPI 自动） |
| 500 | 服务器内部错误 |
| 503 | 上游 AI 服务不可用 |

### 1.3 分页参数

| 参数 | 类型 | 默认 | 说明 |
|---|---|---|---|
| `page` | int | 1 | 页码，≥1 |
| `page_size` | int | 20 | 每页条数，1~100 |

分页响应：

```json
{
  "total": 128,
  "page": 1,
  "page_size": 20,
  "items": []
}
```

### 1.4 客户端接入

Flutter 端通过 `lib/services/api_client.dart` 统一发起请求，**页面不直接调用 HTTP**。

| 运行环境 | 后端地址 |
|---|---|
| Android 模拟器 | `http://10.0.2.2:8000`（默认值，模拟器映射到宿主机） |
| 真机（同一局域网） | 电脑局域网 IP，用 `--dart-define=ANZHI_API_BASE_URL=http://192.168.1.5:8000` 指定 |
| Windows / macOS 桌面 | `http://127.0.0.1:8000` |

客户端约定：

- 超时 10 秒；网络失败、超时、非 2xx、非 JSON 响应**一律翻译成中文提示**，
  页面只处理一种异常类型
- 值为 `null` 或空串的查询参数会被剔除，避免后端收到 `category_id=null` 而返回 422
- 后端只返回 `is_published = true` 的内容，客户端必须正确处理「成功但为空」

---

## 2. 健康检查

### `GET /`

**说明：** 服务存活检查（PROJECT_SPEC 第三十二节）

**响应 200：**

```json
{
  "message": "AnZhi API is running"
}
```

### `GET /api/health`

**响应 200：**

```json
{
  "status": "ok",
  "version": "1.0.0",
  "database": "connected",
  "ai_service": "configured"
}
```

> `ai_service` 只反映**是否已配置 API Key**，不发起真实调用，避免消耗额度。

---

## 3. AI 问答

### `POST /api/chat`

**说明：** AI 安全问答核心接口（PROJECT_SPEC 第三十六节）

**请求体：**

```json
{
  "message": "宿舍发生火灾怎么办？",
  "category": "消防安全",
  "history": []
}
```

| 字段 | 类型 | 必填 | 说明 |
|---|---|:--:|---|
| `message` | string | ✅ | 用户问题，1~1000 字符 |
| `category` | string | ❌ | 指定分类，不传则自动判断 |
| `history` | array | ❌ | 多轮对话上下文 |

**响应 200：**

```json
{
  "question": "宿舍发生火灾怎么办？",
  "category": "消防安全",
  "risk_level": "high",
  "answer": "立即撤离，不要贪恋财物……",
  "steps": [
    "保持冷静，大声呼喊提醒室友",
    "用湿毛巾捂住口鼻，低姿弯腰撤离",
    "不要乘坐电梯，走安全通道",
    "到达安全区域后拨打 119"
  ],
  "sources": ["《中华人民共和国消防法》", "应急管理部消防救援局"],
  "warning": "⚠️ 生命安全优先，切勿返回火场取物。"
}
```

**字段说明：**

| 字段 | 类型 | 说明 |
|---|---|---|
| `risk_level` | string | `low` / `medium` / `high` |
| `steps` | string[] | 可执行步骤，高风险时非空 |
| `sources` | string[] | 来源引用，V1.0 可为空，V2.0 RAG 填充 |
| `warning` | string | 安全警告，medium / high 时非空 |

**错误：**

| 状态码 | 场景 |
|:--:|---|
| 400 | `message` 为空或全空白 |
| 422 | `message` 超过 1000 字符 |
| 503 | DeepSeek 不可用或超时 |

**安全约束（PROJECT_SPEC 第十、十一节、AI_RULES 第十节）：**

> - 高风险问题：回答简洁，优先给出应急措施，**不做长篇科普**
> - 禁止鼓励冒险、禁止危险实验步骤、禁止娱乐化处理紧急情况
> - 信息不足时不得过度确定
> - 回答需经 `SafetyGuard` 审查后才返回给客户端

---

## 4. 知识系统

### `GET /api/categories`

**说明：** 获取六大分类（PROJECT_SPEC 第四节）

**响应 200：**

```json
[
  { "id": 1, "name": "消防安全", "slug": "fire", "icon": "fire", "color": "#E53935", "sort_order": 1 },
  { "id": 2, "name": "用电安全", "slug": "electric", "icon": "bolt", "color": "#FB8C00", "sort_order": 2 }
]
```

### `GET /api/knowledge`

**说明：** 知识列表（PROJECT_SPEC 第三十四节）

**查询参数：**

| 参数 | 类型 | 说明 |
|---|---|---|
| `category_id` | int | 按分类筛选 |
| `risk_level` | string | 按风险等级筛选 |
| `keyword` | string | 标题/简介模糊搜索 |
| `page` / `page_size` | int | 分页 |

**响应 200：**

```json
{
  "total": 24,
  "page": 1,
  "page_size": 20,
  "items": [
    {
      "id": 1,
      "title": "宿舍消防安全",
      "category_id": 1,
      "category_name": "消防安全",
      "summary": "宿舍常见火灾隐患与预防措施",
      "risk_level": "medium",
      "image_url": null,
      "created_at": "2026-09-30T10:00:00"
    }
  ]
}
```

### `GET /api/knowledge/{id}`

**说明：** 知识详情

> **实现进度：** 浏览历史需归属到具体用户，而登录体系属阶段 11，
> 因此「详情接口自动写入浏览历史」与 `view_count` 累加**尚未实现**，
> 计划在阶段 10（知识系统）与阶段 11（收藏 / 历史）补齐。
> 在此之前接口是只读的，不会产生副作用。

**响应 200：**

```json
{
  "id": 1,
  "title": "宿舍消防安全",
  "category_id": 1,
  "category_name": "消防安全",
  "summary": "宿舍常见火灾隐患与预防措施",
  "content": "……正文……",
  "risk_level": "medium",
  "image_url": null,
  "source": "应急管理部",
  "author": "安知编辑部",
  "view_count": 42,
  "created_at": "2026-09-30T10:00:00"
}
```

**错误：** `404` —— 知识不存在或未发布

---

## 5. 收藏

### `POST /api/favorites`

**请求体：**

```json
{ "knowledge_id": 1 }
```

**响应 201：**

```json
{ "id": 1, "knowledge_id": 1, "created_at": "2026-09-30T10:00:00" }
```

> 重复收藏返回 `400`，或幂等返回已存在的记录（实现时二选一并保持一致）。

### `DELETE /api/favorites/{knowledge_id}`

**响应 204：** 无内容

### `GET /api/favorites`

**说明：** 我的收藏列表（PROJECT_SPEC 第三十九节），支持分页

---

## 6. 历史记录

### `GET /api/history`

**说明：** 浏览历史列表（PROJECT_SPEC 第四十节），按 `viewed_at` 倒序，支持分页

### `DELETE /api/history`

**说明：** 清空全部历史

**响应 204：** 无内容

### `DELETE /api/history/{knowledge_id}`

**说明：** 删除单条历史

**响应 204：** 无内容

---

## 7. 社区

| 方法 | 路径 | 说明 | 依据 |
|---|---|---|---|
| `GET` | `/api/posts` | 帖子列表（分页） | 第四十一节 |
| `GET` | `/api/posts/{id}` | 帖子详情（含评论数） | |
| `POST` | `/api/posts` | 发布帖子 | 第四十一节 |
| `DELETE` | `/api/posts/{id}` | 删除自己的帖子 | |
| `GET` | `/api/posts/{id}/comments` | 评论列表 | |
| `POST` | `/api/posts/{id}/comments` | 发表评论 | |
| `POST` | `/api/posts/{id}/like` | 点赞 | |
| `DELETE` | `/api/posts/{id}/like` | 取消点赞 | |

**发布帖子请求体：**

```json
{
  "title": "分享一个防诈骗经验",
  "content": "……",
  "category_id": 5
}
```

**V1.0 不实现：** 私信、关注用户、复杂推荐、AI 审核（PROJECT_SPEC 第二十节）

---

## 8. 个性化

### `GET /api/settings`

**说明：** 获取用户设置（PROJECT_SPEC 第四十二节）

**响应 200：**

```json
{
  "followed_categories": [1, 5],
  "home_modules": ["daily", "ai", "recommend", "category", "community"],
  "notify_enabled": true
}
```

### `PUT /api/settings`

**请求体：** 同响应结构，字段可选

---

## 9. 首页

### `GET /api/home`

**说明：** 首页聚合数据，一次请求返回首页所有模块，减少客户端请求数

**响应 200：**

```json
{
  "daily_knowledge": { "id": 1, "title": "今日安全知识", "summary": "……" },
  "recommended": [],
  "categories": [],
  "community_featured": []
}
```

> V1.0 推荐策略：固定推荐 + 简单用户兴趣（PROJECT_SPEC 第七、十八节），不做复杂算法。

---

## 10. 未来接口（V2.0，暂不实现）

| 路径 | 说明 |
|---|---|
| `POST /api/chat/stream` | SSE 流式回答 |
| `GET /api/search/semantic` | 向量语义检索（RAG） |
| `POST /api/agent/classify` | 问题分类 Agent |

---

## 11. 认证说明

**V1.0：** 采用简单 JWT 认证。受保护接口需携带请求头：

```text
Authorization: Bearer <token>
```

**需要认证的接口：** 收藏、历史、社区发帖/评论/点赞、个性化设置
**无需认证：** 健康检查、分类、知识列表/详情、AI 问答（V1.0）

> **API Key 安全（PROJECT_SPEC 第四十六节）：** DeepSeek API Key 仅存于后端 `.env`，
> Flutter 端不持有、不传递任何第三方密钥，全部经 FastAPI 中转。
