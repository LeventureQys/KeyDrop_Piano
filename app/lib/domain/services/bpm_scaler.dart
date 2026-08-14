import '../models/dk_score.dart';

/// BPM 缩放器（Version 设计文档 2.1 领域服务 BpmScaler）。
///
/// 需求 6 / 决策 F3：BPM 倍率 0.5x-2.0x（步进 0.05x）只改变时间推进速度，
/// 不改变音高。播放时间线 = 实际经过时间 × 倍率。
class BpmScaler {
  const BpmScaler();

  /// 实际经过毫秒 → 播放时间线毫秒。
  ///
  /// 倍率 2.0 时播放时间线流速加倍：原 t 的事件在实际时间 t×0.5 处发生
  /// （Version 验收文档 V3 场景 E）。
  int scaleElapsed(int elapsedMs, double multiplier) =>
      (elapsedMs * multiplier).round();

  /// 播放时间线位置 → 实际经过毫秒（信息栏"实际剩余时间"等场景）。
  int scaleToElapsed(int playbackMs, double multiplier) =>
      (playbackMs / multiplier).round();

  /// 指定播放时刻的实时 BPM（取 tempoMap 中 t ≤ 给定时刻的最后一个事件）。
  double bpmAt(List<DkTempoEvent> tempoMap, int playbackMs) {
    if (tempoMap.isEmpty) {
      return 120.0;
    }
    DkTempoEvent current = tempoMap.first;
    for (final DkTempoEvent e in tempoMap) {
      if (e.t <= playbackMs) {
        current = e;
      } else {
        break;
      }
    }
    return current.bpm;
  }

  /// 当前播放时刻的"小节序号"（1 起）。
  ///
  /// 以 `timeSignature` 的分子为每小节拍数、当前实时 BPM 为拍速，
  /// 变速段的累计误差在 v1.0.0 接受（信息栏展示用途）。
  int barAt(int playbackMs, double currentBpm, int beatsPerBar) {
    if (beatsPerBar <= 0 || currentBpm <= 0) {
      return 1;
    }
    final double beatMs = 60000.0 / currentBpm;
    return (playbackMs / (beatMs * beatsPerBar)).floor() + 1;
  }

  /// 总小节数（按谱面总时长与基础 BPM 估算）。
  int totalBars(DkScore score) {
    final int beatsPerBar = _beatsPerBar(score.meta.timeSignature);
    final double bpm = score.meta.bpmBase > 0
        ? score.meta.bpmBase.toDouble()
        : 120.0;
    if (beatsPerBar <= 0 || bpm <= 0) {
      return 1;
    }
    final double beatMs = 60000.0 / bpm;
    return (score.meta.totalDurationMs / (beatMs * beatsPerBar)).ceil();
  }

  static int _beatsPerBar(String timeSignature) {
    final int slash = timeSignature.indexOf('/');
    if (slash <= 0) {
      return 4;
    }
    return int.tryParse(timeSignature.substring(0, slash)) ?? 4;
  }
}
