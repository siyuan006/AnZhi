import 'package:flutter/material.dart';

import '../pages/login_page.dart';
import 'auth_controller.dart';

/// 安知 —— 打开「需要登录」的页面
///
/// 未登录时**先推登录页，登录成功就顺势把目标页打开**。
///
/// 用户点的是「我的收藏」「通知设置」这类具体入口，意图是明确的；
/// 让他登完再自己回来重按一次是没必要的。反过来直接推目标页也不行 ——
/// 那一页只会显示「请先登录」，等于让他白点一次。
///
/// 本函数**不关心**目标页是否需要登录。所有由它打开的页面自己也要
/// 处理未登录形态（用户在别处退出登录后再回到那一页），
/// 这里只是避免让用户多点一次。
///
/// 返回目标页是否被真正打开过。
Future<bool> openAfterLogin(
  BuildContext context,
  Widget Function() page,
) async {
  final AuthController? auth = AuthScope.maybeOf(context);
  if (auth == null) return false;

  if (!auth.isLoggedIn) {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const LoginPage()),
    );
    // 用户可能是直接返回、没登录就走了
    if (!context.mounted || !auth.isLoggedIn) return false;
  }

  if (!context.mounted) return false;
  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(builder: (_) => page()),
  );
  return true;
}
