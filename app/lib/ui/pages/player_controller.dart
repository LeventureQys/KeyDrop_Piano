import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/models/app_config.dart';
import '../../domain/models/dk_score.dart';
import '../../domain/ports/midi_input_port.dart';
import '../../domain/services/judgment_engine.dart';

/// 游戏阶段。
enum PlayerPhase { ready, playing, paused, finished }

/// 播放器核心控制器。
///
/// 管理时间推进、Note 跟踪、判定、统计。
/// 由外部 Ticker（AnimationController）驱动 `onTick()`。
class PlayerController extends ChangeNotifier {
  PlayerController({
    required this.score,
    required this.config,
    required this.midiInput,
  }) : engine = JudgmentEngine(
          score: score,
          width: config.judgmentWidth,
          latencyOffset: config.inputLatencyOffsetMs,
        ) {
    // 监听 MIDI 输入
    _midiSub = midiInput.events.listen((MidiEvent e) {
      if (e.type == MidiEventType.noteOn) {
        handleKeyPress(e.pitch);
      }
    });
  }

  final DkScore score;
  final AppConfig config;
  final MidiInputPort midiInput;
  final JudgmentEngine engine;

  late final StreamSubscription<MidiEvent> _midiSub;

  PlayerPhase _phase = PlayerPhase.ready;
  PlayerPhase get phase => _phase;

  PlayMode _mode = PlayMode.learning;
  PlayMode get mode => _mode;

  int _currentTimeMs = 0;
  int get currentTimeMs => _currentTimeMs;

  final JudgmentStats stats = JudgmentStats();

  double get fallDurationMs => config.fallDurationSeconds * 1000;

  /// 判定线 Y（相对下落区顶部）。
  static const double judgeLineY = 351;

  /// 当前可视的 Note（未来 fallDurationMs 内）。
  List<DkNote> get visibleNotes {
    final List<DkNote> all =
        score.tracks.isNotEmpty ? score.tracks.first.notes : <DkNote>[];
    return all
        .where((DkNote n) =>
            n.t + n.d >= _currentTimeMs &&
            n.t <= _currentTimeMs + fallDurationMs.toInt() + 200)
        .toList();
  }

  /// 当前等待判定的 Note（学习模式停在判定线）。
  List<DkNote> get waitingNotes => engine.pendingNotes(_currentTimeMs);

  /// 键盘视口偏移（居中当前活跃 note）。
  int get scrollPitch {
    final List<DkNote> active = visibleNotes;
    if (active.isEmpty) return 48; // C3
    int minP = 127;
    int maxP = 0;
    for (final DkNote n in active) {
      if (n.pitch < minP) minP = n.pitch;
      if (n.pitch > maxP) maxP = n.pitch;
    }
    final int mid = (minP + maxP) ~/ 2;
    // 预留 16 键在左
    int start = mid - 16;
    if (start < 21) start = 21;
    if (start > 108 - 32) start = 108 - 32;
    return start;
  }

  /// 最近的高亮键（pitch → color）。
  Map<int, Color> _highlights = <int, Color>{};
  Map<int, Color> get highlights => _highlights;

  void start() {
    if (score.tracks.isEmpty) return;
    _phase = PlayerPhase.playing;
    _mode = config.defaultMode;
    notifyListeners();
  }

  void pause() {
    if (_phase == PlayerPhase.playing) {
      _phase = PlayerPhase.paused;
      midiInput.disconnect();
      notifyListeners();
    }
  }

  void resume() {
    if (_phase == PlayerPhase.paused) {
      _phase = PlayerPhase.playing;
      midiInput.tryConnect();
      notifyListeners();
    }
  }

  /// Ticker 驱动：每帧推进时间。
  void onTick(Duration elapsed) {
    if (_phase != PlayerPhase.playing) return;
    final int newMs =
        (elapsed.inMicroseconds / 1000 * config.bpmMultiplier).round();

    // 学习模式：检查是否有 note 到达判定线需要等待
    if (_mode == PlayMode.learning) {
      final List<DkNote> pending = engine.pendingNotes(newMs);
      if (pending.isNotEmpty && _isWaitingForAny(pending, newMs)) {
        // 不推进时间，等待用户按键
      } else {
        _currentTimeMs = newMs;
      }
    } else {
      _currentTimeMs = newMs;
      // 演奏模式：检查掉 key
      final List<MissedNote> missed = engine.checkMissedNotes(_currentTimeMs);
      stats.miss += missed.length;
    }

    // 检查是否演奏结束
    if (_currentTimeMs >= score.meta.totalDurationMs + 2000) {
      _phase = PlayerPhase.finished;
      _midiSub.cancel();
    }

    notifyListeners();
  }

  void handleKeyPress(int pitch) {
    if (_phase != PlayerPhase.playing) return;
    final JudgmentRecord? rec = engine.onKeyPress(pitch, _currentTimeMs);
    if (rec == null) {
      stats.error++;
    } else {
      switch (rec.result) {
        case JudgmentResult.perfect: stats.perfect++; break;
        case JudgmentResult.early:   stats.early++; break;
        case JudgmentResult.late:    stats.late++; break;
        case JudgmentResult.miss:    stats.miss++; break;
      }
      // 添加高亮
      _highlights = <int, Color>{
        pitch: rec.result == JudgmentResult.perfect
            ? const Color(0xFF16A34A)
            : const Color(0xFFF87171),
      };
      Future<void>.delayed(const Duration(milliseconds: 300), () {
        _highlights = <int, Color>{};
        notifyListeners();
      });
    }
    notifyListeners();
  }

  bool _isWaitingForAny(List<DkNote> pending, int currentMs) {
    for (final DkNote n in pending) {
      final int remaining = n.t - currentMs;
      if (remaining <= 0) return true; // 已过时仍未按 → 卡住
    }
    return false;
  }

  @override
  void dispose() {
    _midiSub.cancel();
    super.dispose();
  }
}
