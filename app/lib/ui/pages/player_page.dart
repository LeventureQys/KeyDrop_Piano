import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../domain/models/app_config.dart';
import '../../domain/models/dk_score.dart';
import '../../domain/ports/lifecycle_port.dart';
import '../../domain/ports/midi_input_port.dart';
import '../../domain/services/statistics_aggregator.dart';
import '../painters/falling_painter.dart';
import '../painters/piano_painter.dart';
import 'player_controller.dart';

/// 下落式播放器页面（Stage 6 设计文档；全屏横屏、三段式布局）。
///
/// 布局比例（原型 1200×540）：信息栏 15% / 下落区 65% / 键盘 20%。
/// 白键宽 = 下落区宽 / viewportKeys（32 键 @1200px = 37px/白键）。
class PlayerPage extends StatefulWidget {
  const PlayerPage({
    super.key,
    required this.score,
    required this.config,
    required this.midiInput,
    required this.lifecycle,
    this.initialMode,
  });

  final DkScore score;
  final AppConfig config;
  final MidiInputPort midiInput;
  final LifecyclePort lifecycle;
  final PlayMode? initialMode;

  @override
  State<PlayerPage> createState() => PlayerPageState();
}

class PlayerPageState extends State<PlayerPage>
    with SingleTickerProviderStateMixin {
  late final PlayerController _ctrl;
  late final Ticker _ticker;
  Timer? _flashTimer;
  bool _flashVisible = false;

  /// 测试句柄：集成测试用它断言时间线/统计（V3 场景 B/C/E）。
  @visibleForTesting
  PlayerController get controller => _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = PlayerController(
      score: widget.score,
      config: widget.config,
      midiInput: widget.midiInput,
    );
    if (widget.initialMode != null) {
      _ctrl.setMode(widget.initialMode!);
    }
    _ctrl.addListener(_onCtrlUpdate);
    // Version 技术栈：下落动画由 Ticker 驱动（不用 Widget 树动画）。
    _ticker = createTicker((Duration elapsed) => _ctrl.onTick(elapsed))
      ..start();
    _ctrl.start();
    // 进入播放器：屏幕常亮（Version 决策表）。
    widget.lifecycle.setKeepScreenOn(true);
  }

  int _lastFlashTick = 0;

  void _onCtrlUpdate() {
    if (_ctrl.errorFlashTick != _lastFlashTick) {
      _lastFlashTick = _ctrl.errorFlashTick;
      setState(() => _flashVisible = true);
      _flashTimer?.cancel();
      _flashTimer = Timer(const Duration(milliseconds: 300), () {
        if (mounted) {
          setState(() => _flashVisible = false);
        }
      });
    }
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _flashTimer?.cancel();
    // 离开播放器：恢复屏幕常亮设置（Version 决策表）。
    widget.lifecycle.setKeepScreenOn(false);
    _ticker.dispose();
    _ctrl.removeListener(_onCtrlUpdate);
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double w = constraints.maxWidth;
            final double h = constraints.maxHeight;
            final double infoH = (h * 0.15).clamp(56.0, 90.0);
            final double keyboardH = (h * 0.20).clamp(84.0, 132.0);
            final double fallingH = h - infoH - keyboardH;
            final double whiteKeyW = w / widget.config.viewportKeys;
            final double blackKeyW = whiteKeyW * 0.6;

            return Stack(
              children: <Widget>[
                Column(
                  children: <Widget>[
                    _buildInfoBar(infoH),
                    _buildFallingArea(fallingH, whiteKeyW, blackKeyW),
                    _buildKeyboard(keyboardH, whiteKeyW, blackKeyW),
                  ],
                ),
                if (_flashVisible) _buildErrorFlash(),
                if (_ctrl.phase == PlayerPhase.paused) _buildPauseOverlay(),
                if (_ctrl.phase == PlayerPhase.finished) _buildResult(),
              ],
            );
          },
        ),
      ),
    );
  }

  // ---------------- 信息栏（E4 + Stage 6 4.5 + 设备状态） ----------------

  Widget _buildInfoBar(double height) {
    final JudgmentStats s = _ctrl.stats;
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF1F2937),
        border: Border(bottom: BorderSide(color: Color(0xFF374151))),
      ),
      child: Row(
        children: <Widget>[
          // 曲名 + 作曲家 + 进度条
          Expanded(
            flex: 4,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  widget.score.meta.title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  widget.score.meta.composer,
                  style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 10),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: widget.score.meta.totalDurationMs > 0
                      ? (_ctrl.currentTimeMs /
                              widget.score.meta.totalDurationMs)
                          .clamp(0.0, 1.0)
                      : 0,
                  backgroundColor: const Color(0xFF374151),
                  color: const Color(0xFF2563EB),
                  minHeight: 3,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // BPM / 拍号 / 调号 / 小节
          _metaChip('BPM', _ctrl.currentBpm.toStringAsFixed(0)),
          _metaChip('拍号', widget.score.meta.timeSignature),
          _metaChip('调号', widget.score.meta.keySignature),
          _metaChip('小节', '${_ctrl.currentBar}/${_ctrl.totalBars}'),
          const SizedBox(width: 8),
          // 设备状态
          _deviceStatus(),
          const SizedBox(width: 8),
          // 实时统计
          _statChip('完美', s.perfect, const Color(0xFF22D3EE)),
          _statChip('抢', s.early, const Color(0xFFFBBF24)),
          _statChip('拖', s.late, const Color(0xFFFB923C)),
          _statChip('掉', s.miss, const Color(0xFF9CA3AF)),
          _statChip('错', s.error, const Color(0xFFEF4444)),
          const SizedBox(width: 8),
          // 模式标签 + 切换
          _modeButton(),
          // 暂停 / 关闭
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

  Widget _metaChip(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(label,
              style: const TextStyle(color: Color(0xFF6B7280), fontSize: 9)),
          Text(value,
              style: const TextStyle(color: Colors.white, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _deviceStatus() {
    final String? name = _ctrl.connectedDeviceName;
    final bool connected = name != null && name.isNotEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: connected
            ? const Color(0xFF16A34A).withAlpha(40)
            : const Color(0xFFEF4444).withAlpha(40),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            connected ? Icons.usb : Icons.usb_off,
            size: 12,
            color: connected
                ? const Color(0xFF22C55E)
                : const Color(0xFFF87171),
          ),
          const SizedBox(width: 4),
          Text(
            connected ? name : '未连接',
            style: TextStyle(
              fontSize: 10,
              color: connected
                  ? const Color(0xFF22C55E)
                  : const Color(0xFFF87171),
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _modeButton() {
    final bool learning = _ctrl.mode == PlayMode.learning;
    return GestureDetector(
      onTap: () => _ctrl.setMode(
          learning ? PlayMode.performance : PlayMode.learning),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: learning ? const Color(0xFF2563EB) : const Color(0xFF7C3AED),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          learning ? '学习' : '演奏',
          style: const TextStyle(color: Colors.white, fontSize: 11),
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
              style: TextStyle(
                  color: color, fontSize: 10, fontWeight: FontWeight.bold)),
          Text('$count',
              style: const TextStyle(color: Color(0xFFD1D5DB), fontSize: 11)),
        ],
      ),
    );
  }

  // ---------------- 下落区 ----------------

  Widget _buildFallingArea(
      double height, double whiteKeyW, double blackKeyW) {
    final Set<int> waiting = <int>{
      for (final DkNote n in _ctrl.waitingNotes) n.t * 256 + n.pitch,
    };
    return SizedBox(
      height: height,
      width: double.infinity,
      child: ClipRect(
        child: CustomPaint(
          painter: FallingPainter(
            notes: _ctrl.visibleNotes,
            currentTimeMs: _ctrl.currentTimeMs,
            fallDurationMs: _ctrl.fallDurationMs,
            fallingAreaHeight: height,
            scrollPitch: _ctrl.scrollPitch,
            whiteKeyW: whiteKeyW,
            blackKeyW: blackKeyW,
            learning: _ctrl.mode == PlayMode.learning,
            waitingIdentities: waiting,
          ),
        ),
      ),
    );
  }

  // ---------------- 键盘（手动滚动模式支持拖动） ----------------

  Widget _buildKeyboard(
      double height, double whiteKeyW, double blackKeyW) {
    return GestureDetector(
      onHorizontalDragUpdate: (DragUpdateDetails d) =>
          _ctrl.dragScroll(d.delta.dx, whiteKeyW),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: PianoPainter(
            viewportKeys: widget.config.viewportKeys,
            scrollPitch: _ctrl.scrollPitch,
            whiteKeyW: whiteKeyW,
            blackKeyW: blackKeyW,
            highlighted: _ctrl.highlights,
          ),
        ),
      ),
    );
  }

  // ---------------- 错音红框脉冲（原型 6px / 300ms） ----------------

  Widget _buildErrorFlash() {
    return IgnorePointer(
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFEF4444), width: 6),
        ),
      ),
    );
  }

  // ---------------- 暂停遮罩（T7：继续/重新开始/退出，原型样式） ----------------

  Widget _buildPauseOverlay() {
    return Container(
      color: Colors.black.withAlpha(179), // rgba(0,0,0,0.7)
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Text('已暂停',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _ctrl.resume,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
            ),
            icon: const Icon(Icons.play_arrow),
            label: const Text('继续'),
          ),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            onPressed: _ctrl.restart,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6B7280),
            ),
            icon: const Icon(Icons.replay),
            label: const Text('重新开始'),
          ),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            onPressed: () => Navigator.of(context).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
            ),
            icon: const Icon(Icons.close),
            label: const Text('退出'),
          ),
        ],
      ),
    );
  }

  // ---------------- 结算页（F2 + Stage 6 4.6 + 原型样式） ----------------

  /// 评级映射（原型 87% → 评级 A）：A ≥ 80 / B ≥ 60 / C ≥ 40 / D ≥ 20 / E。
  static String _ratingOf(double pct) {
    if (pct >= 80) return 'A';
    if (pct >= 60) return 'B';
    if (pct >= 40) return 'C';
    if (pct >= 20) return 'D';
    return 'E';
  }

  Widget _buildResult() {
    final JudgmentStats s = _ctrl.stats;
    final double pct = s.scorePercent;
    final String rating = _ratingOf(pct);
    final Color pctColor = pct >= 80
        ? const Color(0xFF16A34A)
        : pct >= 50
            ? const Color(0xFFFBBF24)
            : const Color(0xFFEF4444);
    return Container(
      color: const Color(0xFF0F172A).withAlpha(242),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Text('演奏完成',
              style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 20)),
          const SizedBox(height: 8),
          Text('${pct.toStringAsFixed(1)}%',
              style: TextStyle(
                  color: pctColor,
                  fontSize: 48,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('评级 $rating',
              style: const TextStyle(
                  color: Color(0xFFFBBF24),
                  fontSize: 20,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 20),
          _resultRow('完美', s.perfect, const Color(0xFF22D3EE)),
          _resultRow('抢拍', s.early, const Color(0xFFFBBF24)),
          _resultRow('拖拍', s.late, const Color(0xFFFB923C)),
          _resultRow('掉键', s.miss, const Color(0xFF9CA3AF)),
          _resultRow('错音', s.error, const Color(0xFFEF4444)),
          const SizedBox(height: 28),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ElevatedButton.icon(
                onPressed: () {
                  setState(_ctrl.restart);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                ),
                icon: const Icon(Icons.replay),
                label: const Text('再来一次'),
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4B5563),
                ),
                icon: const Icon(Icons.arrow_back),
                label: const Text('返回库'),
              ),
            ],
          ),
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
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
