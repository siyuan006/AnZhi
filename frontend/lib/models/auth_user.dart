/// 安知 —— 登录用户模型
///
/// 对应后端 `GET /api/auth/me` 的响应（docs/API.md 第 11 节）。
///
/// ⚠️ 这里**没有** password / passwordHash 字段，而且是刻意的：
/// 后端从不返回它们，客户端也就无从保存。
/// 界面上要显示的口令输入框，读到的值只应该待在一个局部变量里，
/// 用完即弃 —— 不要塞进任何会被序列化、缓存或打日志的对象。
class AuthUser {
  const AuthUser({
    required this.id,
    required this.username,
    this.nickname,
    this.avatarUrl,
    this.studyDays = 0,
  });

  final int id;
  final String username;
  final String? nickname;
  final String? avatarUrl;
  final int studyDays;

  /// 显示用的名字：优先昵称，没有昵称就退回用户名。
  ///
  /// 空字符串要当成「没有」处理 —— 后端把昵称存成 `""` 和存成
  /// `null` 在界面上应该是同一个结果，否则会出现一片空白。
  String get displayName {
    final String? name = nickname;
    if (name != null && name.trim().isNotEmpty) return name.trim();
    return username;
  }

  /// 头像占位用的首字符。
  ///
  /// 用 `runes` 而不是 `substring(0, 1)`：后者按 UTF-16 码元切，
  /// 遇到 emoji 这类代理对字符会切出半个字符，显示成乱码方块。
  String get initial {
    final String name = displayName;
    if (name.isEmpty) return '?';
    return String.fromCharCode(name.runes.first);
  }

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: (json['id'] as num).toInt(),
      username: json['username'] as String? ?? '',
      nickname: json['nickname'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      studyDays: (json['study_days'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AuthUser &&
      other.id == id &&
      other.username == username &&
      other.nickname == nickname &&
      other.avatarUrl == avatarUrl &&
      other.studyDays == studyDays;

  @override
  int get hashCode => Object.hash(id, username, nickname, avatarUrl, studyDays);

  @override
  String toString() => 'AuthUser(id: $id, username: $username)';
}
