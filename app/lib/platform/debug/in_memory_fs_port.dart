import 'dart:convert';
import 'dart:typed_data';

import '../../domain/exceptions/dk_exception.dart';
import '../../domain/ports/file_system_port.dart';

/// 开发/测试用内存文件系统（实现 FileSystemPort）。
///
/// 数据仅存于内存，重启即丢失。用于桌面开发与单元/Widget 测试，
/// 生产环境替换为 [AndroidFileSystemAdapter]。
class InMemoryFileSystemPort implements FileSystemPort {
  InMemoryFileSystemPort();

  /// 预填示例数据（含 5 条谱面）。仅桌面演示用；真实设备由
  /// [AndroidFileSystemAdapter] 提供空库 → 导入引导。
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

  /// 注入的"待选 MIDI"内容（桌面/测试模拟 SAF 选择结果）。
  Uint8List? _pickedMidiBytes;
  String? _pickedMidiName;

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
      throw FileSystemAccessException('File not found: $fileId');
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
    if (entry == null) {
      throw FileSystemAccessException('File not found: $fileId');
    }
    entry.displayName = newName;
    entry._modified = DateTime.now();
  }

  @override
  Future<String?> pickMidiFile() async {
    // 桌面/测试无 SAF：返回注入的伪路径（未注入 = 用户取消）。
    return _pickedMidiBytes != null ? 'memory://${_pickedMidiName ?? 'picked.mid'}' : null;
  }

  @override
  Future<Uint8List?> readMidiFile(String path) async {
    return _pickedMidiBytes;
  }

  @override
  Future<String?> importDkScore() async {
    // 桌面/测试：从注入的伪"外部文件"导入。
    final String? name = _pickedMidiName;
    final Uint8List? bytes = _pickedMidiBytes;
    if (name == null || bytes == null) {
      return null;
    }
    final String content = utf8.decode(bytes);
    // 校验内容确为 DK 谱（含 dkVersion 字段）。
    final Map<String, dynamic> json = jsonDecode(content) as Map<String, dynamic>;
    if (json['dkVersion'] == null) {
      throw FileSystemAccessException('所选文件不是有效的 DK 谱（缺少 dkVersion）。');
    }
    return writeDkScore(
        name.endsWith('.dk.json') ? name : '$name.dk.json', content);
  }

  /// 直接注入 MIDI 字节供转换测试（替代 SAF 选择）。
  void injectMidiBytes(String name, Uint8List bytes) {
    _pickedMidiName = name;
    _pickedMidiBytes = bytes;
  }

  @override
  Future<bool> exportDkScore(String fileId) async {
    return _entries.containsKey(fileId);
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
