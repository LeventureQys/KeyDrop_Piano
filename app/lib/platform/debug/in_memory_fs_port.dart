import 'dart:convert';
import 'dart:typed_data';

import '../../../domain/ports/file_system_port.dart';

/// 开发/测试用内存文件系统（实现 FileSystemPort）。
///
/// 数据仅存于内存，重启即丢失。用于桌面开发与单元测试，
/// 生产环境替换为 [AndroidFileSystemAdapter]。
class InMemoryFileSystemPort implements FileSystemPort {
  InMemoryFileSystemPort();

  /// 预填示例数据（含 5 条谱面）。
  factory InMemoryFileSystemPort.withSampleData() {
    final InMemoryFileSystemPort fs = InMemoryFileSystemPort();
    const List<Map<String, String>> samples = <Map<String, String>>[
      <String, String>{
        'title': '致爱丽丝',
        'composer': '贝多芬',
        'modified': '2026-06-20',
        'size': '124',
      },
      <String, String>{
        'title': '小星星',
        'composer': '传统',
        'modified': '2026-06-18',
        'size': '32',
      },
      <String, String>{
        'title': '卡农',
        'composer': '帕赫贝尔',
        'modified': '2026-06-15',
        'size': '256',
      },
      <String, String>{
        'title': '梦中的婚礼',
        'composer': '克莱德曼',
        'modified': '2026-06-10',
        'size': '198',
      },
      <String, String>{
        'title': '天空之城',
        'composer': '久石让',
        'modified': '2026-06-05',
        'size': '178',
      },
    ];
    for (final Map<String, String> s in samples) {
      fs._addSample(s['title']!, s['composer']!, s['modified']!,
          int.tryParse(s['size']!) ?? 0);
    }
    return fs;
  }

  final Map<String, _FileEntry> _entries = <String, _FileEntry>{};
  int _nextId = 1;

  void _addSample(
      String title, String composer, String modified, int sizeKb) {
    final String id = 'sample_${_nextId++}.dk.json';
    _entries[id] = _FileEntry(
      displayName: title,
      content: jsonEncode(<String, dynamic>{
        'dkVersion': '1.0',
        'meta': <String, dynamic>{
          'title': title,
          'composer': composer,
          'sourceMidiSha256': 'sample',
          'bpmBase': 120,
          'timeSignature': '4/4',
          'keySignature': 'C',
          'totalDurationMs': 30000,
        },
        'tracks': <dynamic>[],
        'tempoMap': <dynamic>[],
      }),
    );
    _entries[id]!._modified = DateTime.parse('$modified 10:00:00');
    _entries[id]!._size = sizeKb * 1024;
  }

  @override
  Future<List<DkScoreFile>> listDkScores() async {
    final List<DkScoreFile> result = <DkScoreFile>[];
    for (final MapEntry<String, _FileEntry> e in _entries.entries) {
      result.add(DkScoreFile(
        fileId: e.key,
        displayName: e.value.displayName,
        sizeBytes: e.value.size,
        modifiedAt: e.value.modified,
      ));
    }
    result.sort((DkScoreFile a, DkScoreFile b) =>
        b.modifiedAt.compareTo(a.modifiedAt));
    return result;
  }

  @override
  Future<String> readDkScore(String fileId) async {
    final _FileEntry? entry = _entries[fileId];
    if (entry == null) {
      throw Exception('File not found: $fileId');
    }
    return entry.content;
  }

  @override
  Future<String> writeDkScore(String fileName, String content) async {
    final String id = 'file_${_nextId++}.dk.json';
    _entries[id] = _FileEntry(displayName: fileName, content: content);
    return id;
  }

  @override
  Future<void> deleteDkScore(String fileId) async {
    _entries.remove(fileId);
  }

  @override
  Future<void> renameDkScore(String fileId, String newName) async {
    final _FileEntry? entry = _entries[fileId];
    if (entry != null) {
      entry.displayName = newName;
      entry._modified = DateTime.now();
    }
  }

  @override
  Future<String?> pickMidiFile() async {
    // Mock: 返回 null 表示用户取消
    return null;
  }

  /// 直接注入 MIDI 字节供转换测试（替代 SAF 选择）。
  Future<void> injectMidiBytes(String name, Uint8List bytes) {
    // 存储到 _tempMidi 字段供 pick 返回
    return Future<void>.value();
  }

  @override
  Future<bool> exportDkScore(String fileId) async {
    return true;
  }
}

class _FileEntry {
  _FileEntry({required this.displayName, required this.content});

  String displayName;
  final String content;
  DateTime _modified = DateTime.now();
  int _size = 0;

  DateTime get modified => _modified;
  int get size =>
      _size > 0 ? _size : content.length; // approximate bytes
}
