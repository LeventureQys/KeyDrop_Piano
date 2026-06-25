import 'dart:convert';

import 'package:flutter/services.dart';

import '../../domain/ports/file_system_port.dart';

/// Android 文件系统适配器（实现 FileSystemPort）。
///
/// 通过 MethodChannel `keydrop_piano/file_system` 与 Kotlin 端通信。
/// 支持私有目录 CRUD + SAF 导入导出。
class AndroidFileSystemAdapter implements FileSystemPort {
  static const MethodChannel _channel =
      MethodChannel('keydrop_piano/file_system');

  @override
  Future<List<DkScoreFile>> listDkScores() async {
    final String json = await _channel.invokeMethod('listDkScores') as String;
    final List<dynamic> list = jsonDecode(json) as List<dynamic>;
    return list.map((dynamic e) {
      final Map<String, dynamic> m = e as Map<String, dynamic>;
      return DkScoreFile(
        fileId: m['fileId'] as String,
        displayName: m['displayName'] as String,
        sizeBytes: (m['sizeBytes'] as num).toInt(),
        modifiedAt: DateTime.tryParse(m['modifiedAt'] as String? ?? '') ??
            DateTime(2000),
      );
    }).toList();
  }

  @override
  Future<String> readDkScore(String fileId) async {
    return await _channel.invokeMethod('readDkScore', <String, dynamic>{
      'fileId': fileId,
    }) as String;
  }

  @override
  Future<String> writeDkScore(String fileName, String content) async {
    return await _channel.invokeMethod('writeDkScore', <String, dynamic>{
      'fileName': fileName,
      'content': content,
    }) as String;
  }

  @override
  Future<void> deleteDkScore(String fileId) async {
    await _channel.invokeMethod('deleteDkScore', <String, dynamic>{
      'fileId': fileId,
    });
  }

  @override
  Future<void> renameDkScore(String fileId, String newName) async {
    await _channel.invokeMethod('renameDkScore', <String, dynamic>{
      'fileId': fileId,
      'newName': newName,
    });
  }

  @override
  Future<String?> pickMidiFile() async {
    try {
      final String? path = await _channel.invokeMethod('pickMidiFile') as String?;
      return path;
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<bool> exportDkScore(String fileId) async {
    try {
      final bool? ok = await _channel.invokeMethod('exportDkScore', <String, dynamic>{
        'fileId': fileId,
      }) as bool?;
      return ok ?? false;
    } on PlatformException {
      return false;
    }
  }
}
