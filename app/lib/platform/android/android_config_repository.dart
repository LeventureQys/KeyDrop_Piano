import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/app_config.dart';
import '../../domain/ports/config_repository_port.dart';

/// Android 配置持久化（实现 ConfigRepositoryPort）。
///
/// 使用 shared_preferences 存储 JSON 序列化的 AppConfig。
class AndroidConfigRepository implements ConfigRepositoryPort {
  static const String _key = 'app_config';

  @override
  Future<AppConfig> load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) {
      return AppConfig.defaults;
    }
    try {
      final Map<String, dynamic> json = jsonDecode(raw) as Map<String, dynamic>;
      return AppConfig.fromJson(json);
    } on FormatException {
      return AppConfig.defaults;
    }
  }

  @override
  Future<void> save(AppConfig config) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String raw = jsonEncode(config.toJson());
    await prefs.setString(_key, raw);
  }
}
