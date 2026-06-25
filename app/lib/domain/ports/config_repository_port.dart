import '../models/app_config.dart';

/// 配置持久化端口（领域层 → 平台层抽象）。
///
/// v1.0.0 Android 实现 = shared_preferences（Stage 4/后续）。
abstract class ConfigRepositoryPort {
  /// 读取配置。无持久化记录时返回 [AppConfig.defaults]。
  Future<AppConfig> load();

  /// 保存配置。
  Future<void> save(AppConfig config);
}
