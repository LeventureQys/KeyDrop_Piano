import 'package:flutter/material.dart';

import '../../domain/models/dk_score.dart';

/// 下落 Key 绘制器 CustomPainter。
///
/// 计算每个 note 的 y 坐标 = `judgeLineY - (note.t - currentTimeMs) * pxPerMs`。
class FallingPainter extends CustomPainter {
  FallingPainter({
    required this.notes,
    required this.currentTimeMs,
    required this.fallDurationMs,
    required this.fallingAreaHeight,
    required this.scrollOffsetPitch,
  });

  final List<DkNote> notes;
  final int currentTimeMs;
  final double fallDurationMs;
  final double fallingAreaHeight;
  final int scrollOffsetPitch;

  static const double whiteKeyW = 37;
  static const double blackKeyW = 22;

  double get _pxPerMs =>
      fallingAreaHeight / fallDurationMs;

  @override
  void paint(Canvas canvas, Size size) {
    final double judgeLineY = size.height;
    final int startPitch = scrollOffsetPitch;

    for (final DkNote n in notes) {
      // 只画在可视范围内的 note（~当前时间前后一段）
      final int ahead = n.t - currentTimeMs;
      final double y = judgeLineY - ahead * _pxPerMs;

      // 超出视口上下的大范围不画
      if (y < -200 || y > size.height + 50) continue;

      final double x = _keyX(n.pitch, startPitch);
      final double w = _isWhite(n.pitch) ? whiteKeyW : blackKeyW;
      final bool isBlack = !_isWhite(n.pitch);

      // 长按尾巴
      final double tailH = n.d * _pxPerMs;
      final Rect tail = Rect.fromLTWH(x, y - tailH, w, tailH);

      final Color noteColor =
          isBlack ? const Color(0xFFA78BFA) : const Color(0xFF60A5FA);
      final Color tailColor =
          isBlack ? const Color(0xFF7C3AED) : const Color(0xFF2563EB);

      // 画尾巴
      canvas.drawRect(
        tail,
        Paint()..color = tailColor.withAlpha(120),
      );

      // 画 note 主体（圆角矩形）
      final RRect body = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y - 14, w, 14),
        const Radius.circular(3),
      );
      canvas.drawRRect(body, Paint()..color = noteColor);
    }

    // 判定线
    final Paint linePaint = Paint()
      ..color = const Color(0xFFFCD34D)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(0, judgeLineY),
      Offset(size.width, judgeLineY),
      linePaint,
    );
  }

  @override
  bool shouldRepaint(covariant FallingPainter oldDelegate) {
    return oldDelegate.currentTimeMs != currentTimeMs ||
        oldDelegate.notes != notes ||
        oldDelegate.fallDurationMs != fallDurationMs ||
        oldDelegate.scrollOffsetPitch != scrollOffsetPitch;
  }

  static double _keyX(int pitch, int startPitch) {
    final int myW = whiteIndex(pitch);
    final int startW = whiteIndex(startPitch);
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

  /// pitch 之前的最近白键的 whiteIndex。
  static int whiteIndexOfPrev(int pitch) {
    var p = pitch - 1;
    while (p >= 0) {
      if (_isWhite(p)) return whiteIndex(p);
      p--;
    }
    return 0;
  }
}
