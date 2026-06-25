import 'package:meta/meta.dart';

/// 键盘滚动模式（Version 设计文档 3.2 / 决策 E1）。
enum ScrollMode { auto, manual, fixed }

/// 判定档位（Version 设计文档 3.2 / 决策 C3）。
enum JudgmentWidth { strict, medium, wide }

/// 播放模式（Version 设计文档 3.2 / 需求 5）。
enum PlayMode { learning, performance }

/// 单次判定结果分类（供 Stage 6 使用）。
enum JudgmentResult { perfect, early, late, miss }

/// 判定窗口数值（毫秒）。
///
/// [perfectMs]：完美窗 ± 值；[lateMaxMs]：拖拍上限，亦即"掉 key"阈值。
@immutable
class JudgmentWindow {
  const JudgmentWindow(this.perfectMs, this.lateMaxMs);

  final int perfectMs;
  final int lateMaxMs;

  @override
  bool operator ==(Object other) =>
      other is JudgmentWindow &&
      other.perfectMs == perfectMs &&
      other.lateMaxMs == lateMaxMs;

  @override
  int get hashCode => Object.hash(perfectMs, lateMaxMs);
}

/// 用户可配置项（Version 设计文档 3.2）。
@immutable
class AppConfig {
  const AppConfig({
    required this.hardwareKeyboardKeys,
    required this.viewportKeys,
    required this.scrollMode,
    required this.fallDurationSeconds,
    required this.judgmentWidth,
    required this.inputLatencyOffsetMs,
    required this.bpmMultiplier,
    required this.defaultMode,
    required this.enableDebugMidiInjector,
  });

  /// 硬件键盘键数：49 | 61 | 76 | 88。
  final int hardwareKeyboardKeys;

  /// UI 视口可见键数：24 | 32 | 40。
  final int viewportKeys;

  final ScrollMode scrollMode;

  /// 下落时长（秒）：1.0 ~ 3.0。
  final double fallDurationSeconds;

  final JudgmentWidth judgmentWidth;

  /// 全局输入延迟补偿（毫秒）：-100 ~ +100。
  final int inputLatencyOffsetMs;

  /// BPM 倍率：0.5 ~ 2.0。
  final double bpmMultiplier;

  final PlayMode defaultMode;

  /// 是否启用 DebugMidiInjector（仅 debug 构建有效；原型设置页"调试"分组）。
  final bool enableDebugMidiInjector;

  /// 默认配置（来源：Version 设计文档第 5 节关键技术决策表）。
  static const AppConfig defaults = AppConfig(
    hardwareKeyboardKeys: 88,
    viewportKeys: 32,
    scrollMode: ScrollMode.auto,
    fallDurationSeconds: 1.5,
    judgmentWidth: JudgmentWidth.wide,
    inputLatencyOffsetMs: 0,
    bpmMultiplier: 1.0,
    defaultMode: PlayMode.learning,
    enableDebugMidiInjector: false,
  );

  AppConfig copyWith({
    int? hardwareKeyboardKeys,
    int? viewportKeys,
    ScrollMode? scrollMode,
    double? fallDurationSeconds,
    JudgmentWidth? judgmentWidth,
    int? inputLatencyOffsetMs,
    double? bpmMultiplier,
    PlayMode? defaultMode,
    bool? enableDebugMidiInjector,
  }) {
    return AppConfig(
      hardwareKeyboardKeys: hardwareKeyboardKeys ?? this.hardwareKeyboardKeys,
      viewportKeys: viewportKeys ?? this.viewportKeys,
      scrollMode: scrollMode ?? this.scrollMode,
      fallDurationSeconds: fallDurationSeconds ?? this.fallDurationSeconds,
      judgmentWidth: judgmentWidth ?? this.judgmentWidth,
      inputLatencyOffsetMs: inputLatencyOffsetMs ?? this.inputLatencyOffsetMs,
      bpmMultiplier: bpmMultiplier ?? this.bpmMultiplier,
      defaultMode: defaultMode ?? this.defaultMode,
      enableDebugMidiInjector:
          enableDebugMidiInjector ?? this.enableDebugMidiInjector,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'hardwareKeyboardKeys': hardwareKeyboardKeys,
        'viewportKeys': viewportKeys,
        'scrollMode': scrollMode.name,
        'fallDurationSeconds': fallDurationSeconds,
        'judgmentWidth': judgmentWidth.name,
        'inputLatencyOffsetMs': inputLatencyOffsetMs,
        'bpmMultiplier': bpmMultiplier,
        'defaultMode': defaultMode.name,
        'enableDebugMidiInjector': enableDebugMidiInjector,
      };

  /// 反序列化。未知枚举值 / 缺失字段回退到默认值，不抛异常（鲁棒性优先）。
  factory AppConfig.fromJson(Map<String, dynamic> json) {
    return AppConfig(
      hardwareKeyboardKeys:
          (json['hardwareKeyboardKeys'] as num?)?.toInt() ??
              defaults.hardwareKeyboardKeys,
      viewportKeys:
          (json['viewportKeys'] as num?)?.toInt() ?? defaults.viewportKeys,
      scrollMode: _enumFromName(
          ScrollMode.values, json['scrollMode'], defaults.scrollMode),
      fallDurationSeconds: (json['fallDurationSeconds'] as num?)?.toDouble() ??
          defaults.fallDurationSeconds,
      judgmentWidth: _enumFromName(
          JudgmentWidth.values, json['judgmentWidth'], defaults.judgmentWidth),
      inputLatencyOffsetMs: (json['inputLatencyOffsetMs'] as num?)?.toInt() ??
          defaults.inputLatencyOffsetMs,
      bpmMultiplier:
          (json['bpmMultiplier'] as num?)?.toDouble() ?? defaults.bpmMultiplier,
      defaultMode: _enumFromName(
          PlayMode.values, json['defaultMode'], defaults.defaultMode),
      enableDebugMidiInjector: json['enableDebugMidiInjector'] as bool? ??
          defaults.enableDebugMidiInjector,
    );
  }

  /// 返回指定档位的判定窗口（Version 设计文档 3.2 表）。
  static JudgmentWindow windowFor(JudgmentWidth w) => switch (w) {
        JudgmentWidth.strict => const JudgmentWindow(15, 30),
        JudgmentWidth.medium => const JudgmentWindow(25, 50),
        JudgmentWidth.wide => const JudgmentWindow(30, 80),
      };

  /// 对一次按键的偏差 [deltaMs] 分类。
  ///
  /// [deltaMs] = 按下时刻 - (key 触底时刻 + inputLatencyOffsetMs)（已补偿）。
  /// 负值 = 早按（抢拍方向），正值 = 晚按（拖拍方向）。
  static JudgmentResult classify(int deltaMs, JudgmentWidth w) {
    final JudgmentWindow win = windowFor(w);
    if (deltaMs.abs() <= win.perfectMs) {
      return JudgmentResult.perfect;
    }
    if (deltaMs < 0) {
      return deltaMs >= -win.lateMaxMs
          ? JudgmentResult.early
          : JudgmentResult.miss;
    }
    return deltaMs <= win.lateMaxMs ? JudgmentResult.late : JudgmentResult.miss;
  }

  static T _enumFromName<T extends Enum>(
      List<T> values, Object? name, T fallback) {
    for (final T v in values) {
      if (v.name == name) {
        return v;
      }
    }
    return fallback;
  }

  @override
  bool operator ==(Object other) =>
      other is AppConfig &&
      other.hardwareKeyboardKeys == hardwareKeyboardKeys &&
      other.viewportKeys == viewportKeys &&
      other.scrollMode == scrollMode &&
      other.fallDurationSeconds == fallDurationSeconds &&
      other.judgmentWidth == judgmentWidth &&
      other.inputLatencyOffsetMs == inputLatencyOffsetMs &&
      other.bpmMultiplier == bpmMultiplier &&
      other.defaultMode == defaultMode &&
      other.enableDebugMidiInjector == enableDebugMidiInjector;

  @override
  int get hashCode => Object.hash(
        hardwareKeyboardKeys,
        viewportKeys,
        scrollMode,
        fallDurationSeconds,
        judgmentWidth,
        inputLatencyOffsetMs,
        bpmMultiplier,
        defaultMode,
        enableDebugMidiInjector,
      );
}
