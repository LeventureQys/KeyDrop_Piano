// ignore_for_file: avoid_print
//
// 分层约束自检脚本（Version 设计文档 2.2 / 禁止事项 F-01 的执行器）。
// 扫描 lib/domain/ 下所有 .dart 文件，检测被禁止的 import；发现违规则以非 0
// 退出码结束并打印 `LAYERING VIOLATION: <文件>:<行号>: <被禁import>`。
//
// 用法（在 app/ 目录下）：dart run tool/check_layering.dart
import 'dart:io';

const List<String> _banned = <String>[
  'package:flutter/',
  'dart:io',
  'dart:ui',
  'package:shared_preferences/',
  '../platform/',
  'package:keydrop_piano/platform/',
];

void main() {
  final Directory domainDir = Directory('lib/domain');
  if (!domainDir.existsSync()) {
    print('LAYERING OK: scanned 0 files in lib/domain (directory absent)');
    exit(0);
  }

  final List<File> files = domainDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((File f) => f.path.endsWith('.dart'))
      .toList();

  final List<String> violations = <String>[];
  var scanned = 0;

  for (final File f in files) {
    scanned++;
    final List<String> lines = f.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final String line = lines[i].trimLeft();
      if (!line.startsWith('import ') && !line.startsWith('export ')) {
        continue;
      }
      for (final String banned in _banned) {
        if (line.contains(banned)) {
          final String rel = f.path.replaceAll('\\', '/');
          violations.add('LAYERING VIOLATION: $rel:${i + 1}: $banned');
        }
      }
    }
  }

  if (violations.isEmpty) {
    print('LAYERING OK: scanned $scanned files in lib/domain');
    exit(0);
  }
  for (final String v in violations) {
    print(v);
  }
  exit(1);
}
