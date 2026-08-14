import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/models/dk_score.dart';

/// 下落 Key 绘制器 CustomPainter（Stage 6 设计文档 4.2 + 原型视觉规范）。
///
/// - y 坐标 = `判定线Y - (note.t - currentTimeMs) * pxPerMs`（下落时长可调）。
/// - 白键音 `#60A5FA`，黑键音 `#A78BFA`；长按尾（d ≥ 200ms）半透明矩形。
/// - 学习模式等待中的 note 钳制在判定线上，`#FACC15` 呼吸动画（0.8s 周期）。
/// - 判定线：`#F59E0B` 发光横线。
class FallingPainter extends CustomPainter {
  FallingPainter({
    required this.notes,
    required this.currentTimeMs,
    required this.fallDurationMs,
    required this.fallingAreaHeight,
    required this.scrollPitch,
    required this.whiteKeyW,
    required this.blackKeyW,
    this.learning = false,
    this.waitingIdentities = const <int>{},
  });

  final List<DkNote> notes;
  final int currentTimeMs;
  final double fallDurationMs;
  final double fallingAreaHeight;
  final int scrollPitch;
  final double whiteKeyW;
  final double blackKeyW;
  final bool learning;
  final Set<int> waitingIdentities;

  static const Color whiteNoteColor = Color(0xFF60A5FA);
  static const Color blackNoteColor = Color(0xFFA78BFA);
  static const Color whiteTailColor = Color(0xFF2563EB);
  static const Color blackTailColor = Color(0xFF7C3AED);
  static const Color waitingColor = Color(0xFFFACC15);
  static const Color judgeLineColor = Color(0xFFF59E0B);

  double get _pxPerMs => fallingAreaHeight / fallDurationMs;

  @override
  void paint(Canvas canvas, Size size) {
    final double judgeLineY = size.height - 2;

    for (final DkNote n in notes) {
      final int identity = n.t * 256 + n.pitch;
      final bool waiting = learning && waitingIdentities.contains(identity);

      final int ahead = n.t - currentTimeMs;
      double y = judgeLineY - ahead * _pxPerMs;
      if (waiting) {
        y = judgeLineY; // 停在判定线上等待
      }

      if (y < -260 || y > size.height + 50) {
        continue;
      }

      final double x = _keyX(n.pitch);
      final double w = _isWhite(n.pitch) ? whiteKeyW : blackKeyW;
      final bool isBlack = !_isWhite(n.pitch);

      // 长按尾巴（E3：duration > 200ms 显示拖尾，长度 = 时长 × 像素/毫秒）。
      if (n.d >= 200) {
        final double tailH = n.d * _pxPerMs;
        final Rect tail = Rect.fromLTWH(x, y - tailH, w, tailH);
        canvas.drawRect(
          tail,
          Paint()
            ..color = (isBlack ? blackTailColor : whiteTailColor).withAlpha(120),
        );
      }

      // note 主体（圆角矩形）
      Color bodyColor = isBlack ? blackNoteColor : whiteNoteColor;
      if (waiting) {
        // 呼吸动画：0.8s 周期，透明度 0.65~1.0。
        final double phase = (currentTimeMs % 800) / 800.0;
        final double breath =
            0.65 + 0.35 * (0.5 + 0.5 * math.sin(phase * 2 * math.pi));
        bodyColor = waitingColor.withAlpha((255 * breath).round());
      }
      final RRect body = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y - 14, w, 14),
        const Radius.circular(3),
      );
      canvas.drawRRect(body, Paint()..color = bodyColor);
    }

    // 判定线（发光）
    final Paint glowPaint = Paint()
      ..color = judgeLineColor.withAlpha(90)
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    final Paint linePaint = Paint()
      ..color = judgeLineColor
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
        Offset(0, judgeLineY), Offset(size.width, judgeLineY), glowPaint);
    canvas.drawLine(
        Offset(0, judgeLineY), Offset(size.width, judgeLineY), linePaint);
  }

  @override
  bool shouldRepaint(covariant FallingPainter oldDelegate) {
    return oldDelegate.currentTimeMs != currentTimeMs ||
        oldDelegate.notes != notes ||
        oldDelegate.fallDurationMs != fallDurationMs ||
        oldDelegate.scrollPitch != scrollPitch ||
        oldDelegate.whiteKeyW != whiteKeyW ||
        oldDelegate.blackKeyW != blackKeyW ||
        oldDelegate.learning != learning ||
        oldDelegate.waitingIdentities != waitingIdentities;
  }

  double _keyX(int pitch) {
    final int myW = whiteIndex(pitch);
    final int startW = whiteIndex(scrollPitch);
    if (_isWhite(pitch)) {
      return (myW - startW).toDouble() * whiteKeyW;
    }
    // 黑键：位于前一个白键和后一个白键之间
    final int prevW = whiteIndexOfPrev(pitch);
    final double left = (prevW - startW).toDouble() * whiteKeyW;
    return left - blackKeyW / 2;
  }

  static bool _isWhite(int pitch) {
    const List<int> whiteInOctave = <int>[0, 2, 4, 5, 7, 9, 11];
    return whiteInOctave.contains(pitch % 12);
  }

  static int whiteIndex(int pitch) {
    const List<int> slotToWhite = <int>[0, -1, 1, -1, 2, 3, -1, 4, -1, 5, -1, 6];
    final int octave = pitch ~/ 12;
    final int w = slotToWhite[pitch % 12];
    return octave * 7 + w;
  }

  static int whiteIndexOfPrev(int pitch) {
    var p = pitch - 1;
    while (p >= 0) {
      if (_isWhite(p)) {
        return whiteIndex(p);
      }
      p--;
    }
    return 0;
  }
}
