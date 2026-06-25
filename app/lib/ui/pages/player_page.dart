import 'package:flutter/material.dart';

import '../../domain/models/app_config.dart';
import '../../domain/models/dk_score.dart';
import '../../domain/ports/midi_input_port.dart';
import '../../domain/services/judgment_engine.dart';
import '../painters/falling_painter.dart';
import '../painters/piano_painter.dart';
import 'player_controller.dart';

/// 下落式播放器页面（全屏横屏固定 1200×540 画布）。
class PlayerPage extends StatefulWidget {
  const PlayerPage({
    super.key,
    required this.score,
    required this.config,
    required this.midiInput,
  });

  final DkScore score;
  final AppConfig config;
  final MidiInputPort midiInput;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage>
    with TickerProviderStateMixin {
  late final PlayerController _ctrl;
  late final AnimationController _ticker;

  @override
  void initState() {
    super.initState();
    _ctrl = PlayerController(
      score: widget.score,
      config: widget.config,
      midiInput: widget.midiInput,
    );
    _ctrl.addListener(_onCtrlUpdate);
    _ticker = AnimationController.unbounded(vsync: this)
      ..addListener(() => _ctrl.onTick(_ticker.lastElapsedDuration ?? Duration.zero));
    _ticker.repeat();
    _ctrl.start();
  }

  void _onCtrlUpdate() {
    setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    _ctrl.removeListener(_onCtrlUpdate);
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Container(
          width: 1200,
          height: 540,
          color: const Color(0xFF0F172A),
          child: _ctrl.phase == PlayerPhase.finished
              ? _buildResult()
              : Column(
                  children: <Widget>[
                    _buildInfoBar(),
                    Expanded(
                      child: _buildFallingArea(),
                    ),
                    _buildKeyboard(),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildInfoBar() {
    final JudgmentStats s = _ctrl.stats;
    return Container(
      height: 81,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF1F2937),
        border: Border(bottom: BorderSide(color: Color(0xFF374151))),
      ),
      child: Row(
        children: <Widget>[
          // 进度条 + 曲名
          Expanded(
            flex: 3,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  widget.score.meta.title,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: widget.score.meta.totalDurationMs > 0
                      ? _ctrl.currentTimeMs /
                          widget.score.meta.totalDurationMs
                      : 0,
                  backgroundColor: const Color(0xFF374151),
                  color: const Color(0xFF2563EB),
                  minHeight: 3,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // 统计
          _statChip('P', s.perfect, const Color(0xFF16A34A)),
          _statChip('E', s.early, const Color(0xFFFBBF24)),
          _statChip('L', s.late, const Color(0xFFF97316)),
          _statChip('M', s.miss, const Color(0xFFEF4444)),
          _statChip('X', s.error, const Color(0xFFF87171)),
          const SizedBox(width: 12),
          // 模式标签 + 暂停按钮
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _ctrl.mode == PlayMode.learning
                  ? const Color(0xFF2563EB)
                  : const Color(0xFF7C3AED),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              _ctrl.mode == PlayMode.learning ? '学习' : '演奏',
              style: const TextStyle(color: Colors.white, fontSize: 11),
            ),
          ),
          IconButton(
            icon: Icon(
              _ctrl.phase == PlayerPhase.paused
                  ? Icons.play_arrow
                  : Icons.pause,
              color: const Color(0xFF9CA3AF),
              size: 20,
            ),
            onPressed: () {
              if (_ctrl.phase == PlayerPhase.paused) {
                _ctrl.resume();
              } else {
                _ctrl.pause();
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Color(0xFF9CA3AF), size: 20),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildFallingArea() {
    final List<DkNote> visible = _ctrl.visibleNotes;
    return GestureDetector(
      onTapDown: (_) {},
      child: CustomPaint(
        size: const Size(1200, 351),
        painter: FallingPainter(
          notes: visible,
          currentTimeMs: _ctrl.currentTimeMs,
          fallDurationMs: _ctrl.fallDurationMs,
          fallingAreaHeight: 351,
          scrollOffsetPitch: _ctrl.scrollPitch,
        ),
      ),
    );
  }

  Widget _buildKeyboard() {
    return SizedBox(
      height: 108,
      width: 1200,
      child: CustomPaint(
        painter: PianoPainter(
          viewportKeys: 32,
          scrollOffsetPitch: _ctrl.scrollPitch,
          highlighted: _ctrl.highlights,
        ),
      ),
    );
  }

  Widget _buildResult() {
    final JudgmentStats s = _ctrl.stats;
    final double pct = s.scorePercent;
    return Container(
      color: const Color(0xFF0F172A),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text('演奏结束',
                style: TextStyle(color: Colors.white, fontSize: 20)),
            const SizedBox(height: 8),
            Text('${pct.toStringAsFixed(1)}%',
                style: TextStyle(
                    color: pct >= 80 ? const Color(0xFF16A34A) : const Color(0xFFFBBF24),
                    fontSize: 48,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            _resultRow('完美', s.perfect, const Color(0xFF16A34A)),
            _resultRow('抢拍', s.early, const Color(0xFFFBBF24)),
            _resultRow('拖拍', s.late, const Color(0xFFF97316)),
            _resultRow('掉键', s.miss, const Color(0xFFEF4444)),
            _resultRow('错音', s.error, const Color(0xFFF87171)),
            const SizedBox(height: 30),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('返回库'),
                ),
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed: () {
                    _ctrl.dispose();
                    _ticker.repeat();
                    setState(() {
                      _ctrl = PlayerController(
                        score: widget.score,
                        config: widget.config,
                        midiInput: widget.midiInput,
                      );
                      _ctrl.addListener(_onCtrlUpdate);
                      _ctrl.start();
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                  ),
                  child: const Text('再来一次'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statChip(String label, int count, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(label,
              style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
          Text('$count',
              style: const TextStyle(color: Color(0xFFD1D5DB), fontSize: 11)),
        ],
      ),
    );
  }

  Widget _resultRow(String label, int count, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 40,
            child: Text(label,
                style: const TextStyle(color: Color(0xFFD1D5DB), fontSize: 14)),
          ),
          Text('$count',
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
