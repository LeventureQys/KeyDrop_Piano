import 'package:flutter/material.dart';

/// 钢琴键盘 CustomPainter（Stage 6 设计文档 4.3 + 原型视觉规范）。
///
/// - 白键宽由视口键数自适应（32 键 @1200px = 37px/白键）；
/// - 黑键叠在白键上，高 60% 键盘区高度，宽为白键 60%；
/// - C 键左边界粗线 + 底部音名标注；
/// - [highlighted] = pitch → Color 的按键高亮（按对绿 / 按错红 / 掉键灰）。
class PianoPainter extends CustomPainter {
  PianoPainter({
    required this.viewportKeys,
    required this.scrollPitch,
    required this.whiteKeyW,
    required this.blackKeyW,
    required this.highlighted,
  });

  /// 视口白键数（24/32/40）。
  final int viewportKeys;

  /// 视口最左端对应的 MIDI pitch。
  final int scrollPitch;
  final double whiteKeyW;
  final double blackKeyW;
  final Map<int, Color> highlighted;

  @override
  void paint(Canvas canvas, Size size) {
    final double keyH = size.height;
    final double blackH = keyH * 0.6;

    final Paint whitePaint = Paint()..color = Colors.white;
    final Paint blackPaint = Paint()..color = const Color(0xFF1F2937);
    final Paint linePaint = Paint()
      ..color = const Color(0xFF6B7280)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final Paint dividerPaint = Paint()
      ..color = const Color(0xFF4B5563)
      ..strokeWidth = 2;

    const List<int> whiteOffsets = <int>[0, 2, 4, 5, 7, 9, 11]; // C D E F G A B

    // 第一遍：白键位置。
    final List<_KeyInfo> whites = <_KeyInfo>[];
    var x = 0.0;
    var pitch = scrollPitch;
    while (x < size.width && pitch <= 108) {
      if (whiteOffsets.contains(pitch % 12)) {
        whites.add(_KeyInfo(pitch, x, x + whiteKeyW));
        x += whiteKeyW;
      }
      pitch++;
    }

    // 画白键。
    for (final _KeyInfo w in whites) {
      final Color? hl = highlighted[w.pitch];
      final Rect rect = Rect.fromLTRB(w.left, 0, w.right, keyH);
      canvas.drawRect(rect, hl != null ? (Paint()..color = hl) : whitePaint);
      canvas.drawRect(rect, linePaint);
    }

    // C 键标注：左边界粗线 + 底部音名。
    final TextPainter tp = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );
    for (final _KeyInfo w in whites) {
      if (w.pitch % 12 == 0) {
        canvas.drawLine(
          Offset(w.left, 0),
          Offset(w.left, keyH),
          dividerPaint,
        );
        final String name = 'C${w.pitch ~/ 12 - 1}';
        tp.text = TextSpan(
          text: name,
          style: const TextStyle(
            color: Color(0xFF6B7280),
            fontSize: 9,
            fontWeight: FontWeight.bold,
          ),
        );
        tp.layout(minWidth: w.right - w.left);
        tp.paint(canvas, Offset(w.left + 2, keyH - 14));
      }
    }

    // 第二遍：黑键（叠在白键上）。
    var wx = 0.0;
    for (int p = scrollPitch; p <= 108 && wx < size.width; p++) {
      if (whiteOffsets.contains(p % 12)) {
        wx += whiteKeyW;
      } else {
        final double cx = wx - blackKeyW / 2;
        if (cx >= 0 && cx + blackKeyW <= size.width) {
          final Color? hl = highlighted[p];
          final Rect rect = Rect.fromLTRB(cx, 0, cx + blackKeyW, blackH);
          canvas.drawRect(
            rect,
            hl != null ? (Paint()..color = hl) : blackPaint,
          );
          canvas.drawRect(rect, linePaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant PianoPainter oldDelegate) {
    return oldDelegate.highlighted != highlighted ||
        oldDelegate.scrollPitch != scrollPitch ||
        oldDelegate.viewportKeys != viewportKeys ||
        oldDelegate.whiteKeyW != whiteKeyW ||
        oldDelegate.blackKeyW != blackKeyW;
  }
}

class _KeyInfo {
  _KeyInfo(this.pitch, this.left, this.right);
  final int pitch;
  final double left;
  final double right;
}
