import 'package:flutter_test/flutter_test.dart';
import 'package:keydrop_piano/domain/models/app_config.dart';
import 'package:keydrop_piano/platform/android/android_config_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('AndroidConfigRepository', () {
    test('无记录时返回 defaults', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final AndroidConfigRepository repo = AndroidConfigRepository();
      final AppConfig c = await repo.load();
      expect(c, AppConfig.defaults);
    });

    test('save → load round-trip', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final AndroidConfigRepository repo = AndroidConfigRepository();

      final AppConfig src = AppConfig.defaults.copyWith(
        viewportKeys: 40,
        bpmMultiplier: 1.25,
        defaultMode: PlayMode.performance,
        enableDebugMidiInjector: true,
      );
      await repo.save(src);
      final AppConfig c = await repo.load();
      expect(c, src);
    });

    test('损坏数据回退 defaults', () async {
      SharedPreferences.setMockInitialValues(
        <String, Object>{'app_config': '{broken'},
      );
      final AndroidConfigRepository repo = AndroidConfigRepository();
      final AppConfig c = await repo.load();
      expect(c, AppConfig.defaults);
    });
  });
}
