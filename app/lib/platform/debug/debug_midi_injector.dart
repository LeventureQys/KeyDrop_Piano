import 'dart:async';

import '../../domain/ports/midi_input_port.dart';

/// 调试用 MIDI 事件注入器（仅 debug 构建使用）。
///
/// 实现 [MidiInputPort]，提供 `inject` 方法供自动化测试注入伪 MIDI 序列，
/// 模拟真实电钢琴输入而无需硬件。connectedDeviceName 固定返回 "Debug Injector"，
/// tryConnect/disconnect 为空操作。
///
/// Stage 7 集成测试 + 无电钢琴演示场景使用。
class DebugMidiInjector implements MidiInputPort {
  final StreamController<MidiEvent> _eventController =
      StreamController<MidiEvent>.broadcast();

  final StreamController<String?> _deviceController =
      StreamController<String?>.broadcast();

  DebugMidiInjector() {
    _deviceController.add('Debug Injector');
  }

  @override
  Stream<String?> get connectedDeviceName => _deviceController.stream;

  @override
  Stream<MidiEvent> get events => _eventController.stream;

  @override
  Future<void> tryConnect() async {}

  @override
  Future<void> disconnect() async {}

  /// 注入一条伪 MIDI 事件到事件流（测试用）。
  void inject(MidiEvent event) {
    _eventController.add(event);
  }

  /// 批量注入事件序列。
  void injectAll(List<MidiEvent> events) {
    for (final MidiEvent e in events) {
      _eventController.add(e);
    }
  }

  /// 关闭内部流。
  void dispose() {
    _eventController.close();
    _deviceController.close();
  }
}
