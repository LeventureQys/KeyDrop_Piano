import 'dart:async';

import '../../domain/ports/midi_input_port.dart';

/// 调试用 MIDI 事件注入器（仅 debug 构建使用，Stage 4.3 契约）。
///
/// 装饰真实 [MidiInputPort]（通常为 [AndroidMidiInputAdapter]）：
/// - `inject` / `injectAll` 把伪 MIDI 事件合并进事件流，供集成测试在无电钢琴
///   环境下模拟真实输入（Version 验收 V3 场景 B/C）；
/// - 其余行为（设备名、tryConnect、disconnect）全部委托给内层端口，
///   因此 debug 构建同时保留真实 USB MIDI 能力（真机验收指南 T4/T5 依赖）。
class DebugMidiInjector implements MidiInputPort {
  DebugMidiInjector(this._inner);

  /// 无内层端口时（纯测试/无平台实现），inner 传 null 即可。
  DebugMidiInjector.none() : _inner = null;

  final MidiInputPort? _inner;

  final StreamController<MidiEvent> _injectedController =
      StreamController<MidiEvent>.broadcast();

  Stream<MidiEvent>? _mergedEvents;

  @override
  Stream<String?> get connectedDeviceName {
    final MidiInputPort? inner = _inner;
    if (inner != null) {
      return inner.connectedDeviceName;
    }
    return Stream<String?>.value('Debug Injector');
  }

  @override
  Stream<MidiEvent> get events {
    final MidiInputPort? inner = _inner;
    if (inner == null) {
      return _injectedController.stream;
    }
    return _mergedEvents ??=
        _mergeStreams(<Stream<MidiEvent>>[inner.events, _injectedController.stream]);
  }

  static Stream<MidiEvent> _mergeStreams(List<Stream<MidiEvent>> streams) {
    late StreamController<MidiEvent> controller;
    controller = StreamController<MidiEvent>.broadcast(onListen: () {
      for (final Stream<MidiEvent> s in streams) {
        s.listen(controller.add);
      }
    });
    return controller.stream;
  }

  @override
  Future<void> tryConnect() async {
    await _inner?.tryConnect();
  }

  @override
  Future<void> disconnect() async {
    await _inner?.disconnect();
  }

  /// 注入一条伪 MIDI 事件到事件流（测试用）。
  void inject(MidiEvent event) {
    _injectedController.add(event);
  }

  /// 批量注入事件序列。
  void injectAll(List<MidiEvent> events) {
    for (final MidiEvent e in events) {
      _injectedController.add(e);
    }
  }

  /// 关闭内部流。
  void dispose() {
    _injectedController.close();
  }
}
