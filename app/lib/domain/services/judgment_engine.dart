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

  /// 唯一身份键：(t, pitch)。DK 谱生成器已保证同 (t,pitch) 去重，
  /// 因此 (t,pitch) 可唯一定位一个待判 note（含和弦场景）。
  int get identity => noteT * 256 + pitch;
}

/// 掉 key 记录（仅演奏模式产生）。
class MissedNote {
  const MissedNote(this.note, this.timeMs);
  final DkNote note;
  final int timeMs;
}

/// 判定引擎（领域层纯逻辑，Version 设计文档 3.2 + F2/F4/F5 + Stage 6 4.4）。
///
/// 核心契约：
/// - 偏差公式：`deltaMs = 按下时刻 - (key 触底时刻 + latencyOffset)`
///   （Version 设计文档 3.2："所有时间均按 按下时刻 - (key 触底时刻 + inputLatencyOffsetMs) 计算"）。
/// - 和弦（F4）：同一 `t` 的多个不同 pitch 分别独立判定，全部按齐才算通过；
///   一个 pitch 的按键**不得**吞掉同 t 的其他 pitch。
/// - 长按（F5）：v1.0.0 仅判按下时刻，不判定时长。
/// - 错音（F2）：按下不在判定窗口内的其他键 → 计 [errorCount]，不影响其余判定。
///
/// 学习模式（[learningMode] = true）：
/// - 匹配范围放宽为"已到达判定线（t + offset 已过）的未判定 note"，无窗口上限——
///   学习模式下 key 会等待用户，不允许因等待过久把正确键判为 miss；
/// - 分类时把 |delta| 截断到拖拍窗内再调用 [AppConfig.classify]，
///   保证正确键只落在 {perfect, early, late}，不会变 miss。
class JudgmentEngine {
  JudgmentEngine({
    required this.score,
    required this.width,
    required this.latencyOffset,
    this.learningMode = false,
  }) : _notesByPitch = _buildIndex(score);

  final DkScore score;
  final JudgmentWidth width;
  final int latencyOffset;

  /// 学习模式开关（由播放器在模式切换时更新）。
  bool learningMode;

  final Map<int, List<DkNote>> _notesByPitch;

  /// 全部判定记录（含 miss）。
  final List<JudgmentRecord> records = <JudgmentRecord>[];

  /// 错音次数（按下无匹配 note 的键）。
  int errorCount = 0;

  /// 已判定（含 miss）note 的 identity 集合。
  final Set<int> _judged = <int>{};

  List<DkNote> get _allNotes =>
      score.tracks.isNotEmpty ? score.tracks.first.notes : <DkNote>[];

  int _lateMax() => AppConfig.windowFor(width).lateMaxMs;

  static int _identity(DkNote n) => n.t * 256 + n.pitch;

  /// 指定 note 是否已被判定（含 miss）。
  bool hasJudged(DkNote n) => _judged.contains(_identity(n));

  /// 重置全部判定状态（"再来一次"）。
  void reset() {
    records.clear();
    errorCount = 0;
    _judged.clear();
  }

  /// 指定播放时刻仍在判定窗口内的未判定 note（供 UI 高亮/学习模式等待）。
  List<DkNote> pendingNotes(int currentTimeMs) {
    final List<DkNote> result = <DkNote>[];
    for (final DkNote n in _allNotes) {
      if (_judged.contains(_identity(n))) {
        continue;
      }
      final int line = n.t + latencyOffset;
      final int windowStart = line - _lateMax();
      final int windowEnd = line + _lateMax();
      if (currentTimeMs >= windowStart && currentTimeMs <= windowEnd) {
        result.add(n);
      }
    }
    return result;
  }

  /// 是否还有"已到达判定线（触底）但未判定"的 note。
  /// 学习模式用它冻结时间线：存在即卡住等待。
  bool hasDueUnjudgedNotes(int currentTimeMs) {
    for (final DkNote n in _allNotes) {
      if (_judged.contains(_identity(n))) {
        continue;
      }
      if (currentTimeMs >= n.t + latencyOffset) {
        return true;
      }
    }
    return false;
  }

  /// 最接近且未判定的"到期" note 的触底时刻（学习模式时间线吸附用）。
  /// 没有到期 note 时返回 null。
  int? dueNoteTime(int currentTimeMs) {
    int? earliest;
    for (final DkNote n in _allNotes) {
      if (_judged.contains(_identity(n))) {
        continue;
      }
      if (currentTimeMs >= n.t + latencyOffset) {
        final int line = n.t + latencyOffset;
        if (earliest == null || line < earliest) {
          earliest = line;
        }
      }
    }
    return earliest;
  }

  /// 是否全部 note 均已判定（学习模式结束条件）。
  bool get allNotesJudged {
    if (_allNotes.isEmpty) {
      return true;
    }
    return _judged.length == _allNotes.length;
  }

  /// 处理一次用户按键。
  ///
  /// 匹配规则：
  /// - 偏差公式：`delta = 按下时刻 - (触底时刻 + latencyOffset)`（Version 3.2）。
  /// - 演奏模式：仅匹配 |delta| < lateMax 的未判定 note。
  /// - 学习模式：匹配 `delta >= -lateMax` 的未判定 note（到期后无上限，
  ///   因为 key 会等待用户）；**太早的按键（delta < -lateMax）不匹配**，
  ///   避免提前吞掉未来音符。
  /// - 返回 null = 错音（无匹配），[errorCount] 已自增。
  JudgmentRecord? onKeyPress(int pitch, int pressTimeMs) {
    final List<DkNote> candidates = _notesByPitch[pitch] ?? <DkNote>[];
    if (candidates.isEmpty) {
      errorCount++;
      return null;
    }

    DkNote? best;
    var bestDist = 1 << 30;
    for (final DkNote n in candidates) {
      if (_judged.contains(_identity(n))) {
        continue;
      }
      final int delta = pressTimeMs - (n.t + latencyOffset);
      if (delta < -_lateMax()) {
        continue; // 过早按键，不吞未来 note
      }
      if (!learningMode && delta > _lateMax()) {
        continue; // 演奏模式：已过期，掉 key 由 checkMissedNotes 处理
      }
      final int absDelta = delta.abs();
      if (absDelta < bestDist) {
        best = n;
        bestDist = absDelta;
      }
    }
    if (best == null) {
      errorCount++;
      return null; // pitch 匹配但全部已判定 / 窗口外
    }

    final int delta = pressTimeMs - (best.t + latencyOffset);
    final JudgmentResult result;
    if (learningMode) {
      // 学习模式：正确键不允许变 miss，分类截断在 {early, perfect, late} 内。
      final int clamped = delta.clamp(-_lateMax(), _lateMax());
      result = AppConfig.classify(clamped, width);
    } else {
      result = AppConfig.classify(delta, width);
    }

    final JudgmentRecord rec = JudgmentRecord(
      pitch: pitch,
      result: result,
      timeMs: pressTimeMs,
      noteT: best.t,
    );
    records.add(rec);
    if (result != JudgmentResult.miss) {
      _judged.add(rec.identity);
    }
    return rec;
  }

  /// 演奏模式下检查过期的未判定 note（掉 key）。
  ///
  /// 同一 note 只会被记为一次 miss；学习模式不应调用本方法。
  List<MissedNote> checkMissedNotes(int currentTimeMs) {
    final List<MissedNote> missed = <MissedNote>[];
    for (final DkNote n in _allNotes) {
      final int identity = _identity(n);
      if (_judged.contains(identity)) {
        continue;
      }
      final int deadline = n.t + latencyOffset + _lateMax();
      if (currentTimeMs > deadline) {
        missed.add(MissedNote(n, currentTimeMs));
        records.add(JudgmentRecord(
          pitch: n.pitch,
          result: JudgmentResult.miss,
          timeMs: currentTimeMs,
          noteT: n.t,
        ));
        _judged.add(identity);
      }
    }
    return missed;
  }

  static Map<int, List<DkNote>> _buildIndex(DkScore score) {
    final Map<int, List<DkNote>> map = <int, List<DkNote>>{};
    if (score.tracks.isEmpty) {
      return map;
    }
    for (final DkNote n in score.tracks.first.notes) {
      map.putIfAbsent(n.pitch, () => <DkNote>[]).add(n);
    }
    return map;
  }
}
