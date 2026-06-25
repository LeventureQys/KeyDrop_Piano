import 'package:meta/meta.dart';

/// App 私有目录中的一个 DK 谱文件描述（Version 设计文档 3.4）。
@immutable
class DkScoreFile {
  const DkScoreFile({
    required this.fileId,
    required this.displayName,
    required this.sizeBytes,
    required this.modifiedAt,
  });

  /// 内部 ID（文件名 hash 或路径）。
  final String fileId;

  /// 用户可见名称。
  final String displayName;

  final int sizeBytes;

  final DateTime modifiedAt;

  @override
  bool operator ==(Object other) =>
      other is DkScoreFile &&
      other.fileId == fileId &&
      other.displayName == displayName &&
      other.sizeBytes == sizeBytes &&
      other.modifiedAt == modifiedAt;

  @override
  int get hashCode =>
      Object.hash(fileId, displayName, sizeBytes, modifiedAt);
}

/// 文件系统端口（领域层 → 平台层抽象，Version 设计文档 3.4）。
///
/// v1.0.0 Android 实现 = App 私有目录 (getExternalFilesDir) + SAF（Stage 4）。
abstract class FileSystemPort {
  /// 列出 App 私有目录下所有 .dk.json 文件。
  Future<List<DkScoreFile>> listDkScores();

  /// 读取指定 .dk.json 文件内容。
  Future<String> readDkScore(String fileId);

  /// 写入 .dk.json 到 App 私有目录，返回新文件 ID。
  Future<String> writeDkScore(String fileName, String content);

  /// 删除指定文件。
  Future<void> deleteDkScore(String fileId);

  /// 重命名指定文件。
  Future<void> renameDkScore(String fileId, String newName);

  /// 通过 SAF 选择外部 MIDI 文件，返回临时复制路径（取消返回 null）。
  Future<String?> pickMidiFile();

  /// 通过 SAF 将指定 .dk.json 导出到用户选定位置，返回是否成功。
  Future<bool> exportDkScore(String fileId);
}
