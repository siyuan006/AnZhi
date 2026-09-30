import 'package:flutter/material.dart';

import 'app.dart';

/// 安知 —— AI 安全知识科普助手
///
/// 应用入口。
///
/// 页面代码在 `pages/`，通用组件在 `widgets/`，数据模型在 `models/`，
/// 主题与常量在 `core/`，网络请求在 `services/`（阶段 7 加入）。
/// 本文件只保留入口职责，不承载业务逻辑（AI_RULES 第七节）。
void main() {
  runApp(const AnZhiApp());
}
