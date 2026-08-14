import 'dart:convert';

import 'package:flutter/services.dart';

import '../../domain/exceptions/dk_exception.dart';
import '../../domain/ports/file_system_port.dart';

/// Android 文件系统适配器（实现 FileSystemPort）。
///
/// 通过 MethodChannel `keydrop_piano/file_system` 与 Kotlin 端通信。
/// 支持私有目录 CRUD + SAF 导入导出 + 临时 MIDI 字节读取。
/// 任何平台异常统一映射为 [FileSystemAccessException]（Version 3.5）。
class AndroidFileSystemAdapter implements FileSystemPort {
  static const MethodChannel _channel =
      MethodChannel('keydrop_piano/file_system');

  @override
  Future<List<DkScoreFile>> listDkScores() async {
    try {
      final String json = await _channel.invokeMethod('listDkScores') as String;
      final List<dynamic> list = jsonDecode(json) as List<dynamic>;
      return list.map((dynamic e) {
        final Map<String, dynamic> m = e as Map<String, dynamic>;
        return DkScoreFile(
          fileId: m['fileId'] as String,
          displayName: m['displayName'] as String,
          sizeBytes: (m['sizeBytes'] as num).toInt(),
          modifiedAt: _parseModified(m['modifiedAt'] as String?),
        );
      }).toList();
    } on PlatformException catch (e) {
      throw FileSystemAccessException(e.message ?? '列出谱面失败。');
    }
  }

  @override
  Future<String> readDkScore(String fileId) async {
    try {
      return await _channel.invokeMethod('readDkScore', <String, dynamic>{
        'fileId': fileId,
      }) as String;
    } on PlatformException catch (e) {
      throw FileSystemAccessException(e.message ?? '读取谱面失败。');
    }
  }

  @override
  Future<String> writeDkScore(String fileName, String content) async {
    try {
      return await _channel.invokeMethod('writeDkScore', <String, dynamic>{
        'fileName': fileName,
        'content': content,
      }) as String;
    } on PlatformException catch (e) {
      throw FileSystemAccessException(e.message ?? '保存谱面失败。');
    }
  }

  @override
  Future<void> deleteDkScore(String fileId) async {
    try {
      await _channel.invokeMethod('deleteDkScore', <String, dynamic>{
        'fileId': fileId,
      });
    } on PlatformException catch (e) {
      throw FileSystemAccessException(e.message ?? '删除谱面失败。');
    }
  }

  @override
  Future<void> renameDkScore(String fileId, String newName) async {
    try {
      await _channel.invokeMethod('renameDkScore', <String, dynamic>{
        'fileId': fileId,
        'newName': newName,
      });
    } on PlatformException catch (e) {
      throw FileSystemAccessException(e.message ?? '重命名失败。');
    }
  }

  @override
  Future<String?> pickMidiFile() async {
    try {
      return await _channel.invokeMethod('pickMidiFile') as String?;
    } on PlatformException catch (e) {
      throw FileSystemAccessException(e.message ?? '选择 MIDI 文件失败。');
    }
  }

  @override
  Future<Uint8List?> readMidiFile(String path) async {
    try {
      final Object? raw = await _channel.invokeMethod('readMidiFile',
          <String, dynamic>{'path': path});
      if (raw is Uint8List) {
        return raw;
      }
      if (raw is List<int>) {
        return Uint8List.fromList(raw);
      }
      return null;
    } on PlatformException catch (e) {
      throw FileSystemAccessException(e.message ?? '读取 MIDI 文件失败。');
    }
  }

  @override
  Future<String?> importDkScore() async {
    try {
      return await _channel.invokeMethod('importDkScore') as String?;
    } on PlatformException catch (e) {
      throw FileSystemAccessException(e.message ?? '导入 DK 谱失败。');
    }
  }

  @override
  Future<bool> exportDkScore(String fileId) async {
    try {
      final bool? ok = await _channel.invokeMethod('exportDkScore',
          <String, dynamic>{
        'fileId': fileId,
      }) as bool?;
      return ok ?? false;
    } on PlatformException catch (e) {
      throw FileSystemAccessException(e.message ?? '导出 DK 谱失败。');
    }
  }

  /// 兼容两种时间格式：ISO8601（Kotlin 端标准输出）与历史
  /// "yyyy-MM-dd HH:mm"。解析失败回退 Unix epoch。
  static DateTime _parseModified(String? raw) {
    if (raw == null || raw.isEmpty) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
    final DateTime? iso = DateTime.tryParse(raw);
    if (iso != null) {
      return iso;
    }
    // 历史格式 "2026-06-23 10:00" → 手动解析（本地时区）。
    final RegExp legacy = RegExp(r'^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})$');
    final RegExpMatch? m = legacy.firstMatch(raw);
    if (m != null) {
      return DateTime(
        int.parse(m.group(1)!),
        int.parse(m.group(2)!),
        int.parse(m.group(3)!),
        int.parse(m.group(4)!),
        int.parse(m.group(5)!),
      );
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }
}
