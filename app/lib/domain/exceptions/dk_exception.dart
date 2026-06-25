/// DK 谱领域异常体系（Version 设计文档 3.5）。
///
/// 所有领域层 / 平台层抛出的业务异常都应是 [DkException] 的子类。
/// UI 层捕获到任一 [DkException] 时统一弹 AlertDialog 显示 [message]，不崩溃。
///
/// 命名说明：Version 3.5 中文件系统异常写作 `FileSystemException`，但
/// `dart:io` 已存在同名类，为避免歧义与误导入，本项目统一命名为
/// [FileSystemAccessException]（语义不变）。
sealed class DkException implements Exception {
  String get message;
}

/// MIDI 文件格式不受支持（如 SMF 格式 2、压缩 MIDI、含不支持的标志位等）。
class UnsupportedMidiFormatException extends DkException {
  UnsupportedMidiFormatException(this.message);

  @override
  final String message;

  @override
  String toString() => 'UnsupportedMidiFormatException: $message';
}

/// MIDI 文件损坏（chunk header / 长度字段 / 事件读取失败等）。
class CorruptedMidiException extends DkException {
  CorruptedMidiException(this.message);

  @override
  final String message;

  @override
  String toString() => 'CorruptedMidiException: $message';
}

/// DK 谱版本高于当前 App 支持的版本。
class DkVersionTooHighException extends DkException {
  DkVersionTooHighException(this.message);

  @override
  final String message;

  @override
  String toString() => 'DkVersionTooHighException: $message';
}

/// MIDI 设备连接 / 断开失败。
class MidiDeviceConnectionException extends DkException {
  MidiDeviceConnectionException(this.message);

  @override
  final String message;

  @override
  String toString() => 'MidiDeviceConnectionException: $message';
}

/// 文件系统访问失败（读写、SAF 选择、删除、重命名等）。
class FileSystemAccessException extends DkException {
  FileSystemAccessException(this.message);

  @override
  final String message;

  @override
  String toString() => 'FileSystemAccessException: $message';
}
