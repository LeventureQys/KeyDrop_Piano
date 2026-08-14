import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/models/app_config.dart';
import '../../domain/models/dk_score.dart';
import '../../domain/ports/midi_input_port.dart';
import '../../domain/services/bpm_scaler.dart';
import '../../domain/services/judgment_engine.dart';
import '../../domain/services/statistics_aggregator.dart';

/// 游戏阶段。
enum PlayerPhase { ready, playing, paused, finished }

/// 播放器核心控制器（Stage 6 设计文档 4.1 PlayerNotifier 的页面级实现）。
///
/// 职责：时间线推进（Ticker 驱动 × BPM 倍率）、学习模式冻结等待、
/// 演奏模式掉 key 检查、判定接入、统计汇总、键盘视口滚动。
/// **判定与统计逻辑全部在领域层**（[JudgmentEngine] / [StatisticsAggregator] /
/// [BpmScaler]），本控制器只做编排与 UI 状态。
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
    engine.learningMode = config.defaultMode == PlayMode.learning;
    _mode = config.defaultMode;
    _midiSub = midiInput.events.listen((MidiEvent e) {
      if (e.type == MidiEventType.noteOn) {
        handleKeyPress(e.pitch);
      }
    });
    _deviceSub = midiInput.connectedDeviceName.listen((String? name) {
      _connectedDeviceName = name;
      notifyListeners();
    });
  }

  final DkScore score;
  final AppConfig config;
  final MidiInputPort midiInput;
  final JudgmentEngine engine;

  static const BpmScaler _scaler = BpmScaler();
  static const StatisticsAggregator _aggregator = StatisticsAggregator();

  late final StreamSubscription<MidiEvent> _midiSub;
  late final StreamSubscription<String?> _deviceSub;

  String? _connectedDeviceName;
  String? get connectedDeviceName => _connectedDeviceName;

  PlayerPhase _phase = PlayerPhase.ready;
  PlayerPhase get phase => _phase;

  PlayMode _mode = PlayMode.learning;
  PlayMode get mode => _mode;

  /// 播放时间线位置（毫秒，已含 BPM 倍率）。
  int _currentTimeMs = 0;
  int get currentTimeMs => _currentTimeMs;

  /// 上一次 tick 的 ticker 时间（增量推进用，天然支持暂停恢复）。
  Duration _lastElapsed = Duration.zero;

  /// start/restart 后下一次 tick 仅重置时间基线（防止时间跳变）。
  bool _needTimeBaseline = true;

  /// 键盘视口最左端 MIDI pitch（A0=21 .. C8=108）。
  int _lastAutoScroll = 48;

  /// 手动滚动模式下的用户偏移。
  int _manualScrollPitch = 48;

  /// 键面高亮：pitch → color。
  final Map<int, Color> _highlights = <int, Color>{};
  Map<int, Color> get highlights => Map<int, Color>.unmodifiable(_highlights);

  /// 错音红框闪烁计数（UI 监听变化触发整屏脉冲，原型 300ms）。
  int _errorFlashTick = 0;
  int get errorFlashTick => _errorFlashTick;

  /// 实时统计（由领域层聚合器从引擎原始记录汇总）。
  JudgmentStats get stats =>
      _aggregator.aggregate(engine.records, engine.errorCount);

  double get fallDurationMs => config.fallDurationSeconds * 1000;

  /// 当前可视的 Note（未来 fallDurationMs 内，含仍在渲染的长按尾）。
  List<DkNote> get visibleNotes {
    final List<DkNote> all =
        score.tracks.isNotEmpty ? score.tracks.first.notes : <DkNote>[];
    return all
        .where((DkNote n) =>
            n.t + n.d >= _currentTimeMs &&
            n.t <= _currentTimeMs + fallDurationMs.toInt() + 200)
        .toList();
  }

  /// 学习模式下正在判定线等待的 note（到期未判定）。
  List<DkNote> get waitingNotes {
    final List<DkNote> result = <DkNote>[];
    final List<DkNote> all =
        score.tracks.isNotEmpty ? score.tracks.first.notes : <DkNote>[];
    for (final DkNote n in all) {
      if (engine.hasJudged(n)) {
        continue;
      }
      if (_currentTimeMs >= n.t + config.inputLatencyOffsetMs) {
        result.add(n);
      }
    }
    return result;
  }

  /// 当前实时 BPM（tempoMap 当前段 × 倍率），信息栏展示。
  double get currentBpm =>
      _scaler.bpmAt(score.tempoMap, _currentTimeMs) * config.bpmMultiplier;

  /// 当前小节 / 总小节。
  int get currentBar => _scaler.barAt(
      _currentTimeMs, _scaler.bpmAt(score.tempoMap, _currentTimeMs), _beatsPerBar);
  int get totalBars => _scaler.totalBars(score);

  int get _beatsPerBar {
    final int slash = score.meta.timeSignature.indexOf('/');
    if (slash <= 0) {
      return 4;
    }
    return int.tryParse(score.meta.timeSignature.substring(0, slash)) ?? 4;
  }

  /// 键盘视口起始 pitch（按滚动模式）。
  int get scrollPitch {
    switch (config.scrollMode) {
      case ScrollMode.manual:
        return _clampStart(_manualScrollPitch);
      case ScrollMode.fixed:
        return _clampStart(60 - config.viewportKeys ~/ 2); // 居中 C4
      case ScrollMode.auto:
        return _clampStart(_autoScrollPitch());
    }
  }

  int _autoScrollPitch() {
    // E1：预读未来 2 秒的活跃音域，视口居中。
    final int lookaheadEnd = _currentTimeMs + 2000;
    final List<DkNote> all =
        score.tracks.isNotEmpty ? score.tracks.first.notes : <DkNote>[];
    int minP = 127;
    int maxP = 0;
    for (final DkNote n in all) {
      if (n.t >= _currentTimeMs && n.t <= lookaheadEnd) {
        if (n.pitch < minP) {
          minP = n.pitch;
        }
        if (n.pitch > maxP) {
          maxP = n.pitch;
        }
      }
    }
    if (minP > maxP) {
      return _lastAutoScroll; // 无前瞻 note，保持
    }
    final int mid = (minP + maxP) ~/ 2;
    _lastAutoScroll = _clampStart(mid - config.viewportKeys ~/ 2);
    return _lastAutoScroll;
  }

  int _clampStart(int start) {
    final int maxStart = 108 - config.viewportKeys + 1;
    if (start < 21) {
      return 21;
    }
    if (start > maxStart) {
      return maxStart;
    }
    return start;
  }

  /// 手动滚动：拖动键盘（向右拖 = 视口右移、看到更高音）。
  void dragScroll(double dxPixels, double whiteKeyWidth) {
    if (config.scrollMode != ScrollMode.manual) {
      return;
    }
    final int keys = (dxPixels / whiteKeyWidth).round();
    _manualScrollPitch = _clampStart(_manualScrollPitch + keys);
    notifyListeners();
  }

  /// 开始（进入 playing）。
  void start() {
    if (score.tracks.isEmpty || score.tracks.first.notes.isEmpty) {
      _phase = PlayerPhase.finished;
      notifyListeners();
      return;
    }
    _phase = PlayerPhase.playing;
    _needTimeBaseline = true;
    midiInput.tryConnect().catchError((Object _) {});
    notifyListeners();
  }

  void pause() {
    if (_phase == PlayerPhase.playing) {
      _phase = PlayerPhase.paused;
      notifyListeners();
    }
  }

  void resume() {
    if (_phase == PlayerPhase.paused) {
      _phase = PlayerPhase.playing;
      notifyListeners();
    }
  }

  /// 切换学习/演奏模式（V8：播放器内切换）。判定记录保留。
  void setMode(PlayMode next) {
    if (_mode == next) {
      return;
    }
    _mode = next;
    engine.learningMode = next == PlayMode.learning;
    notifyListeners();
  }

  /// 重新开始：全新引擎，时间归零。
  void restart() {
    engine.reset();
    _currentTimeMs = 0;
    _highlights.clear();
    _needTimeBaseline = true;
    _phase = PlayerPhase.playing;
    notifyListeners();
  }

  /// Ticker 驱动：每帧增量推进时间线（BPM 倍率应用于此）。
  void onTick(Duration elapsed) {
    if (_phase != PlayerPhase.playing) {
      return;
    }
    if (_needTimeBaseline) {
      // 只重置基线，不推进时间（start/restart 后的第一帧）。
      _lastElapsed = elapsed;
      _needTimeBaseline = false;
      return;
    }
    final double dtMs =
        (elapsed - _lastElapsed).inMicroseconds / 1000.0;
    _lastElapsed = elapsed;
    if (dtMs <= 0) {
      return;
    }

    final int newMs = _currentTimeMs + (dtMs * config.bpmMultiplier).round();

    if (mode == PlayMode.learning) {
      if (engine.hasDueUnjudgedNotes(newMs)) {
        // 学习模式：key 停在判定线上等待（时间线吸附到判定线）。
        final int? due = engine.dueNoteTime(newMs);
        if (due != null) {
          _currentTimeMs = due;
        }
      } else {
        _currentTimeMs = newMs;
      }
    } else {
      _currentTimeMs = newMs;
      final List<MissedNote> missed = engine.checkMissedNotes(_currentTimeMs);
      for (final MissedNote m in missed) {
        _flashPitch(m.note.pitch, const Color(0xFF9CA3AF), 250);
      }
    }

    _checkFinish();
    notifyListeners();
  }

  void _checkFinish() {
    if (_phase == PlayerPhase.finished) {
      return;
    }
    if (mode == PlayMode.learning) {
      if (engine.allNotesJudged) {
        _phase = PlayerPhase.finished;
      }
    } else if (_currentTimeMs >= score.meta.totalDurationMs + 2000) {
      _phase = PlayerPhase.finished;
    }
    if (_phase == PlayerPhase.finished) {
      _midiSub.cancel();
      _deviceSub.cancel();
    }
  }

  /// 处理一次用户按键（来自 MIDI noteOn）。
  void handleKeyPress(int pitch) {
    if (_phase != PlayerPhase.playing) {
      return;
    }
    final JudgmentRecord? rec = engine.onKeyPress(pitch, _currentTimeMs);
    if (rec == null) {
      // 错音：红框脉冲 + 该键红色高亮 0.5s（F1/F2）。
      _errorFlashTick++;
      _flashPitch(pitch, const Color(0xFFEF4444), 500);
      notifyListeners();
      return;
    }
    final Color color = switch (rec.result) {
      JudgmentResult.perfect => const Color(0xFF22C55E),
      JudgmentResult.early => const Color(0xFFFBBF24),
      JudgmentResult.late => const Color(0xFFFB923C),
      JudgmentResult.miss => const Color(0xFF9CA3AF),
    };
    _flashPitch(pitch, color, rec.result == JudgmentResult.perfect ? 200 : 350);
    notifyListeners();
  }

  void _flashPitch(int pitch, Color color, int durationMs) {
    _highlights[pitch] = color;
    Future<void>.delayed(Duration(milliseconds: durationMs), () {
      if (_highlights[pitch] == color) {
        _highlights.remove(pitch);
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    _midiSub.cancel();
    _deviceSub.cancel();
    super.dispose();
  }
}
