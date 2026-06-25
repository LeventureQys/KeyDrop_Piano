import 'package:meta/meta.dart';

/// MIDI 事件类型（Version 设计文档 3.3）。
enum MidiEventType { noteOn, noteOff, controlChange, other }

/// 一条实时 MIDI 事件（Version 设计文档 3.3）。
@immutable
class MidiEvent {
  const MidiEvent({
    required this.type,
    required this.channel,
    required this.pitch,
    required this.velocity,
    required this.controllerNumber,
    required this.controllerValue,
    required this.timestampUs,
  });

  final MidiEventType type;

  /// 0-15。
  final int channel;

  /// 仅 noteOn / noteOff 有效。
  final int pitch;

  /// 仅 noteOn / noteOff 有效。
  final int velocity;

  /// 仅 controlChange 有效。
  final int controllerNumber;

  /// 仅 controlChange 有效。
  final int controllerValue;

  /// 平台时间戳（微秒），用于延迟分析。
  final int timestampUs;

  @override
  bool operator ==(Object other) =>
      other is MidiEvent &&
      other.type == type &&
      other.channel == channel &&
      other.pitch == pitch &&
      other.velocity == velocity &&
      other.controllerNumber == controllerNumber &&
      other.controllerValue == controllerValue &&
      other.timestampUs == timestampUs;

  @override
  int get hashCode => Object.hash(type, channel, pitch, velocity,
      controllerNumber, controllerValue, timestampUs);
}

/// MIDI 实时输入端口（领域层 → 平台层抽象）。
///
/// v1.0.0 仅 USB OTG 实现（Stage 4 Android）。领域层与 UI 层仅依赖本接口。
abstract class MidiInputPort {
  /// 当前已连接设备名（null = 无连接）。
  Stream<String?> get connectedDeviceName;

  /// 实时 MIDI 事件流。
  Stream<MidiEvent> get events;

  /// 主动扫描并尝试连接首个 USB MIDI 设备。
  Future<void> tryConnect();

  /// 断开当前设备。
  Future<void> disconnect();
}
