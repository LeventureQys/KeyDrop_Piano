import 'package:flutter_test/flutter_test.dart';
import 'package:keydrop_piano/domain/models/app_config.dart';

void main() {
  group('AppConfig defaults (C1)', () {
    test('默认值逐字段符合 Version 决策表', () {
      const AppConfig d = AppConfig.defaults;
      expect(d.hardwareKeyboardKeys, 88);
      expect(d.viewportKeys, 32);
      expect(d.scrollMode, ScrollMode.auto);
      expect(d.fallDurationSeconds, 1.5);
      expect(d.judgmentWidth, JudgmentWidth.wide);
      expect(d.inputLatencyOffsetMs, 0);
      expect(d.bpmMultiplier, 1.0);
      expect(d.defaultMode, PlayMode.learning);
      expect(d.enableDebugMidiInjector, isFalse);
    });
  });

  group('AppConfig copyWith (C2)', () {
    test('单字段覆盖，其余不变', () {
      final AppConfig c =
          AppConfig.defaults.copyWith(viewportKeys: 40, bpmMultiplier: 1.5);
      expect(c.viewportKeys, 40);
      expect(c.bpmMultiplier, 1.5);
      expect(c.hardwareKeyboardKeys, AppConfig.defaults.hardwareKeyboardKeys);
      expect(c.judgmentWidth, AppConfig.defaults.judgmentWidth);
      expect(c.defaultMode, AppConfig.defaults.defaultMode);
    });
  });

  group('AppConfig JSON (C3/C4)', () {
    test('C3 round-trip 含枚举 name', () {
      final AppConfig src = AppConfig.defaults.copyWith(
        scrollMode: ScrollMode.fixed,
        judgmentWidth: JudgmentWidth.strict,
        defaultMode: PlayMode.performance,
        inputLatencyOffsetMs: 18,
        enableDebugMidiInjector: true,
      );
      final AppConfig decoded = AppConfig.fromJson(src.toJson());
      expect(decoded, equals(src));
      expect(src.toJson()['scrollMode'], 'fixed');
      expect(src.toJson()['judgmentWidth'], 'strict');
      expect(src.toJson()['defaultMode'], 'performance');
    });

    test('C4 未知枚举值回退默认且不抛', () {
      final Map<String, dynamic> json = AppConfig.defaults.toJson();
      json['scrollMode'] = 'nonsense';
      json['judgmentWidth'] = 42;
      json['defaultMode'] = null;
      final AppConfig decoded = AppConfig.fromJson(json);
      expect(decoded.scrollMode, AppConfig.defaults.scrollMode);
      expect(decoded.judgmentWidth, AppConfig.defaults.judgmentWidth);
      expect(decoded.defaultMode, AppConfig.defaults.defaultMode);
    });
  });

  group('judgment window (C5)', () {
    test('三档窗口数值正确', () {
      expect(AppConfig.windowFor(JudgmentWidth.strict),
          const JudgmentWindow(15, 30));
      expect(AppConfig.windowFor(JudgmentWidth.medium),
          const JudgmentWindow(25, 50));
      expect(AppConfig.windowFor(JudgmentWidth.wide),
          const JudgmentWindow(30, 80));
    });
  });

  group('classify (C6)', () {
    test('wide 档 perfect/early/late/miss', () {
      const JudgmentWidth w = JudgmentWidth.wide;
      expect(AppConfig.classify(0, w), JudgmentResult.perfect);
      expect(AppConfig.classify(30, w), JudgmentResult.perfect);
      expect(AppConfig.classify(-30, w), JudgmentResult.perfect);
      expect(AppConfig.classify(-50, w), JudgmentResult.early);
      expect(AppConfig.classify(-80, w), JudgmentResult.early);
      expect(AppConfig.classify(50, w), JudgmentResult.late);
      expect(AppConfig.classify(80, w), JudgmentResult.late);
      expect(AppConfig.classify(81, w), JudgmentResult.miss);
      expect(AppConfig.classify(-81, w), JudgmentResult.miss);
    });

    test('strict 档边界', () {
      const JudgmentWidth w = JudgmentWidth.strict;
      expect(AppConfig.classify(15, w), JudgmentResult.perfect);
      expect(AppConfig.classify(-25, w), JudgmentResult.early);
      expect(AppConfig.classify(25, w), JudgmentResult.late);
      expect(AppConfig.classify(40, w), JudgmentResult.miss);
      expect(AppConfig.classify(-40, w), JudgmentResult.miss);
    });

    test('medium 档边界', () {
      const JudgmentWidth w = JudgmentWidth.medium;
      expect(AppConfig.classify(25, w), JudgmentResult.perfect);
      expect(AppConfig.classify(-40, w), JudgmentResult.early);
      expect(AppConfig.classify(40, w), JudgmentResult.late);
      expect(AppConfig.classify(60, w), JudgmentResult.miss);
    });
  });
}
