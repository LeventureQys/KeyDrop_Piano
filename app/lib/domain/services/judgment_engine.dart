import '../../domain/models/app_config.dart';
import '../../domain/models/dk_score.dart';

/// 演奏中一次判定的结果记录。
class JudgmentRecord {
  const JudgmentRecord({
    required this.pitch,
    required this.result,
    required this.timeMs,
    required this.noteT,
  });

  final int pitch;
  final JudgmentResult result;
  final int timeMs;
  final int noteT; // 对应 note 的 t
}

/// 掉 key 记录（仅演奏模式）。
class MissedNote {
  const MissedNote(this.note, this.timeMs);
  final DkNote note;
  final int timeMs;
}

/// 判定引擎（领域层纯逻辑）。
///
/// 对接 DkScore + 实时 MIDI 按键事件，输出 [`JudgmentRecord`] /
/// [`MissedNote`] 供 UI 层消费。
class JudgmentEngine {
  JudgmentEngine({
    required this.score,
    required this.width,
    required this.latencyOffset,
  }) : _notesByPitch = _buildIndex(score);

  final DkScore score;
  final JudgmentWidth width;
  final int latencyOffset;

  final Map<int, List<DkNote>> _notesByPitch;
  final List<JudgmentRecord> records = <JudgmentRecord>[];

  /// 获取指定时间应该开始判定的 note（t 在 currentMs + latency 窗口内）。
  List<DkNote> pendingNotes(int currentTimeMs) {
    final List<DkNote> result = <DkNote>[];
    final List<DkNote> allNotes = score.tracks.isNotEmpty
        ? score.tracks.first.notes
        : <DkNote>[];
    for (final DkNote n in allNotes) {
      final int windowStart = n.t - latencyOffset - _lateMax();
      final int windowEnd = n.t - latencyOffset + _lateMax();
      if (currentTimeMs >= windowStart && currentTimeMs <= windowEnd) {
        result.add(n);
      }
    }
    return result;
  }

  /// 处理一次用户按键。
  ///
  /// 返回 null = 按键不匹配任何待判 note（记 errorCount，由调用方处理）。
  JudgmentRecord? onKeyPress(int pitch, int pressTimeMs) {
    final List<DkNote> candidates = _notesByPitch[pitch] ?? <DkNote>[];
    if (candidates.isEmpty) {
      return null; // error: 按了不在谱面中的键
    }

    // 找距离 pressTimeMs 最近的未判定 note
    DkNote? best;
    var bestDist = 1 << 30;
    for (final DkNote n in candidates) {
      if (_isJudged(n)) continue;
      final int delta = pressTimeMs - n.t;
      final int absDelta = delta.abs();
      if (absDelta < _lateMax() && absDelta < bestDist) {
        best = n;
        bestDist = absDelta;
      }
    }
    if (best == null) {
      return null; // error: pitch 匹配但已过窗口
    }

    final int delta = pressTimeMs - best.t;
    final JudgmentResult result = AppConfig.classify(delta, width);
    final JudgmentRecord rec = JudgmentRecord(
      pitch: pitch,
      result: result,
      timeMs: pressTimeMs,
      noteT: best.t,
    );
    records.add(rec);
    return rec;
  }

  /// 演奏模式下检查过期的未判定 note（掉 key）。
  List<MissedNote> checkMissedNotes(int currentTimeMs) {
    final List<MissedNote> missed = <MissedNote>[];
    final List<DkNote> allNotes = score.tracks.isNotEmpty
        ? score.tracks.first.notes
        : <DkNote>[];
    for (final DkNote n in allNotes) {
      if (_isJudged(n)) continue;
      final int deadline = n.t - latencyOffset + _lateMax();
      if (currentTimeMs > deadline) {
        missed.add(MissedNote(n, currentTimeMs));
        records.add(JudgmentRecord(
          pitch: n.pitch,
          result: JudgmentResult.miss,
          timeMs: currentTimeMs,
          noteT: n.t,
        ));
      }
    }
    return missed;
  }

  bool _isJudged(DkNote n) {
    return records.any(
        (JudgmentRecord r) => r.noteT == n.t && r.result != JudgmentResult.miss);
  }

  int _lateMax() => AppConfig.windowFor(width).lateMaxMs;

  static Map<int, List<DkNote>> _buildIndex(DkScore score) {
    final Map<int, List<DkNote>> map = <int, List<DkNote>>{};
    if (score.tracks.isEmpty) return map;
    for (final DkNote n in score.tracks.first.notes) {
      map.putIfAbsent(n.pitch, () => <DkNote>[]).add(n);
    }
    return map;
  }
}

/// 演奏统计汇总。
class JudgmentStats {
  int perfect = 0;
  int early = 0;
  int late = 0;
  int miss = 0;
  int error = 0;

  double get scorePercent {
    final int total = perfect + early + late + miss + error;
    if (total == 0) return 100.0;
    return (perfect * 100 + early * 70 + late * 70) / total.toDouble();
  }
}

JudgmentStats computeStats(List<JudgmentRecord> records, int errorCount) {
  final JudgmentStats s = JudgmentStats();
  s.error = errorCount;
  for (final JudgmentRecord r in records) {
    switch (r.result) {
      case JudgmentResult.perfect: s.perfect++; break;
      case JudgmentResult.early:   s.early++; break;
      case JudgmentResult.late:    s.late++; break;
      case JudgmentResult.miss:    s.miss++; break;
    }
  }
  return s;
}
