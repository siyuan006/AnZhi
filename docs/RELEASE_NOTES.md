# 版本发布说明

## v1.0.0

安知 AnZhi —— AI 安全知识科普助手，首个可安装版本。

### 这个版本有什么

| 模块 | 内容 |
|---|---|
| AI 安全问答 | 结构化回答（结论 / 处置步骤 / 风险等级），三级风险系统，高风险问题优先给应急处置 |
| 安全知识库 | 六大分类知识卡片，详情页正文 + 浏览计数 |
| 知识库引用 | 回答附带本项目已发布卡片的引用，可点开读原文（**关键词检索，非语义检索**） |
| 账号 | 注册 / 登录 / JWT 鉴权 |
| 收藏与历史 | 收藏知识、自动记录浏览历史 |
| 社区 | 帖子列表 / 详情 / 评论 / 点赞 / 发帖 / 我的帖子 / 删帖 |
| 个性化 | 关注领域（影响推荐排序）、首页布局开关、通知设置 |

技术栈：Flutter 3.47.5 + FastAPI + SQLite + DeepSeek API。

### 附件

| 文件 | 大小 | 说明 |
|---|---|---|
| `app-release.apk` | 49.1 MB | 通用包，含 arm64-v8a / armeabi-v7a / x86_64 |

```
sha256  818197b0524a98550305d176537e2b8ba7c97746fecd11e3375c30afcf250ac3
包名     com.anzhi.anzhi        versionName 1.0.0   versionCode 1
minSdk   24（Android 7.0）       targetSdk 36
签名     Android Debug（见下方「关于签名」）
```

### 安装与使用

这个 APK **不含后端**，需要自己把后端跑起来才能用。后端地址是编译期写死在
包里，本附件内置的是 `http://127.0.0.1:8000`。

```bash
# 1. 手机 USB 连电脑，开启 USB 调试
adb reverse tcp:8000 tcp:8000

# 2. 电脑上启动后端
cd backend
python -m venv .venv
.venv\Scripts\pip.exe install -r requirements.txt
.venv\Scripts\python.exe -m app.database.init_db
.venv\Scripts\python.exe -m uvicorn app.main:app --port 8000

# 3. 安装 APK
adb install -r app-release.apk
```

`adb reverse` 把手机的 `127.0.0.1:8000` 转发到电脑的 8000 端口，所以手机不必和
电脑在同一个 Wi-Fi 下。它是**一次性**的，拔掉数据线重插后要重新执行。

> 换成局域网 IP 需要重新构建：正式包只对 `10.0.2.2` / `127.0.0.1` /
> `localhost` 放行明文 HTTP，用 `http://192.168.x.x:8000` 得先把该地址加进
> `frontend/android/app/src/main/res/xml/network_security_config.xml`，
> 再用 `flutter build apk --release --dart-define=ANZHI_API_BASE_URL=...` 构建。

### 关于签名

本附件用的是 **Android Debug 签名**。它可以正常安装、正常使用，但不适合正式
分发：同一个 `applicationId` 下换了签名，用户必须先卸载旧版才能装新版。

仓库里没有、也不应该有正式密钥（`android/.gitignore` 已忽略
`key.properties` 与 `*.jks` / `*.keystore` / `*.p12` / `*.pfx`）。
要自己出正式包，见 README「APK 打包（阶段 17）」一节的签名部分。

### 已知限制

这些是**如实记录**的未完成项，不是故障：

| 项目 | 现状 |
|---|---|
| AI 问答需要 API Key | 仓库里没有 Key。未配置时 `/api/chat` 返回 **503 + 中文说明**，`/api/health` 报 `ai_service: "not_configured"`。配上 `DEEPSEEK_API_KEY` 即可 |
| 知识内容待审核 | 12 条初稿已入库但均为「待审核」，未发布的内容在接口层一律视为不存在，因此首页显示「暂无内容」。审核发布后即可显示 |
| 登录状态不持久化 | App 关闭后要重新登录。持久化需要存储插件（如 `shared_preferences`），属新增第三方依赖，按 AI_RULES 第五节未擅自引入 |
| 通知开关不生效 | V1.0 没有推送功能。开关会存下偏好，但页面上明说「V1.0 还没有通知推送功能」 |
| 检索是关键词匹配 | 问法里不含知识库用过的词就检索不到。语义检索要 Embedding + 向量库，属更换技术栈，未擅自引入 |
| 社区搜索未实现 | 按钮点了会如实标注「后续版本」，而不是没反应 |
| APK 未在真机实测安装 | 开发机没有连接 Android 设备，也未安装模拟器组件。已验证到包本身合法：`apksigner verify`、`zipalign -c`、zip 结构、`aapt dump badging` 均通过 |

### 验证情况

| 层次 | 命令 | 结果 |
|---|---|---|
| 前端静态检查 | `flutter analyze` | 无问题 |
| 前端测试 | `flutter test` | 366 通过 / 70 跳过（跳过的是需要真实后端的集成测试） |
| 后端测试 | `pytest` | 547 通过 |
| 真实后端联调 | 见 README | 需先启动后端 |

前端测试里包含一组 768 次渲染的界面适配用例：16 个页面 × 3 种屏幕尺寸
（320x568 / 360x640 / 411x867）× 4 档系统字号（1.0 / 1.3 / 1.5 / 2.0）×
4 种数据状态（正常 / 失败 / 空 / 加载中），同时断言不出现布局溢出、
且该出现的状态确实出现。
