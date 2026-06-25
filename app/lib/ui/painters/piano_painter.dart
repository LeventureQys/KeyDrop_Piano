import 'package:flutter/material.dart';

/// 32 键钢琴键盘 CustomPainter。
///
/// [scrollOffsetPitch] = 视口最左端对应的 MIDI pitch。
/// [highlighted] = pitch → Color 的按键高亮映射（按对绿/按错红）。
class PianoPainter extends CustomPainter {
  PianoPainter({
    required this.viewportKeys,
    required this.scrollOffsetPitch,
    required this.highlighted,
  });

  final int viewportKeys;
  final int scrollOffsetPitch;
  final Map<int, Color> highlighted;

  static const double whiteKeyW = 37;
  static const double blackKeyW = 22;

  @override
  void paint(Canvas canvas, Size size) {
    final double keyH = size.height;
    final double blackH = keyH * 0.6;

    final Paint whitePaint = Paint()..color = Colors.white;
    final Paint blackPaint = Paint()..color = const Color(0xFF1F2937);
    final Paint linePaint = Paint()
      ..color = const Color(0xFF374151)
      ..strokeWidth = 1;
    final Paint dividerPaint = Paint()
      ..color = const Color(0xFF4B5563)
      ..strokeWidth = 2;

    // 收集黑白键信息
    final List<_KeyInfo> whites = <_KeyInfo>[];
    final List<_KeyInfo> blacks = <_KeyInfo>[];

    // 构建 88 键全集的视觉映射（A0=21 到 C8=108）
    // 按 octave 模式：白键位置序列
    const List<int> whiteOffsets = <int>[0, 2, 4, 5, 7, 9, 11]; // C D E F G A B
    var x = 0.0;
    int pitch = scrollOffsetPitch;
    while (x < size.width && pitch <= 108) {
      final int octBase = (pitch ~/ 12) * 12;
      final int offset = pitch - octBase;
      final bool isWhite = whiteOffsets.contains(offset);
      if (isWhite) {
        whites.add(_KeyInfo(pitch, x, x + whiteKeyW, 0, keyH));
        x += whiteKeyW;
      }
      pitch++;
    }

    // 重新扫描绘制黑键（基于白键间距）
    var wx = 0.0;
    for (int p = scrollOffsetPitch;
        p <= 108 && wx < size.width;
        p++) {
      final int octBase = (p ~/ 12) * 12;
      final int offset = p - octBase;
      final bool isWhite = whiteOffsets.contains(offset);
      if (isWhite) {
        wx += whiteKeyW;
      } else {
        // 黑键：位于前一个白键的右边缘居中
        final double cx = wx - blackKeyW / 2;
        if (cx >= 0 && cx + blackKeyW <= size.width) {
          blacks.add(_KeyInfo(p, cx, cx + blackKeyW, 0, blackH));
        }
      }
    }

    // 画白键
    for (final _KeyInfo w in whites) {
      final Color? hl = highlighted[w.pitch];
      final Rect rect = Rect.fromLTRB(w.left, 0, w.right, keyH);
      canvas.drawRect(rect, hl != null ? (Paint()..color = hl) : whitePaint);
      canvas.drawRect(rect, linePaint);
    }

    // C 键标注分隔线
    for (final _KeyInfo w in whites) {
      if (w.pitch % 12 == 0) {
        // C 键左边界画粗线
        canvas.drawLine(
          Offset(w.left, 0),
          Offset(w.left, keyH),
          dividerPaint,
        );
      }
    }

    // 画黑键
    for (final _KeyInfo b in blacks) {
      final Color? hl = highlighted[b.pitch];
      final Rect rect = Rect.fromLTRB(b.left, 0, b.right, blackH);
      canvas.drawRect(
        rect,
        hl != null ? (Paint()..color = hl) : blackPaint,
      );
      canvas.drawRect(rect, linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant PianoPainter oldDelegate) {
    return oldDelegate.highlighted != highlighted ||
        oldDelegate.scrollOffsetPitch != scrollOffsetPitch;
  }
}

class _KeyInfo {
  _KeyInfo(this.pitch, this.left, this.right, this.top, this.bottom);
  final int pitch;
  final double left;
  final double right;
  final double top;
  final double bottom;
}
