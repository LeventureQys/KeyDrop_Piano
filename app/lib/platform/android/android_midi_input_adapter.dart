import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import '../../domain/ports/midi_input_port.dart';

/// Android MIDI 实时输入适配器（实现 MidiInputPort）。
///
/// EventChannel `keydrop_piano/midi_events` 接收 11 字节固定包：
///   [0]: status, [1]: data1, [2]: data2, [3-10]: timestampUs（大端 64 位）
/// EventChannel `keydrop_piano/midi_device` 接收 UTF-8 字节数组或 null。
class AndroidMidiInputAdapter implements MidiInputPort {
  AndroidMidiInputAdapter() {
    _init();
  }

  late final StreamController<String?> _deviceController =
      StreamController<String?>.broadcast();

  late final StreamController<MidiEvent> _eventController =
      StreamController<MidiEvent>.broadcast();

  @override
  Stream<String?> get connectedDeviceName => _deviceController.stream;

  @override
  Stream<MidiEvent> get events => _eventController.stream;

  static const EventChannel _eventChannel =
      EventChannel('keydrop_piano/midi_events');
  static const EventChannel _deviceChannel =
      EventChannel('keydrop_piano/midi_device');
  static const MethodChannel _controlChannel =
      MethodChannel('keydrop_piano/midi_control');

  void _init() {
    _deviceChannel.receiveBroadcastStream().listen((dynamic data) {
      if (data == null) {
        _deviceController.add(null);
      } else if (data is List<int>) {
        _deviceController.add(_decodeUtf8(data));
      } else if (data is Uint8List) {
        _deviceController.add(_decodeUtf8(data));
      }
    });

    _eventChannel.receiveBroadcastStream().listen((dynamic data) {
      if (data is! Uint8List) return;
      final List<Uint8List> packets = splitMidiPackets(data);
      for (final Uint8List packet in packets) {
        final MidiEvent? event = decodeMidiPacket(packet);
        if (event != null) {
          _eventController.add(event);
        }
      }
    });
  }

  @override
  Future<void> tryConnect() async {
    await _controlChannel.invokeMethod('tryConnect');
  }

  @override
  Future<void> disconnect() async {
    await _controlChannel.invokeMethod('disconnect');
  }

  /// 按 11 字节固定包切分。[公开以示测试]。
  static List<Uint8List> splitMidiPackets(Uint8List data) {
    const int kPacketSize = 11;
    final List<Uint8List> packets = <Uint8List>[];
    var offset = 0;
    while (offset + kPacketSize <= data.length) {
      packets.add(Uint8List.sublistView(data, offset, offset + kPacketSize));
      offset += kPacketSize;
    }
    return packets;
  }

  /// 解码 11 字节固定包为 MidiEvent。[公开以示测试]。
  static MidiEvent? decodeMidiPacket(Uint8List packet) {
    if (packet.length < 11) return null;
    final int status = packet[0];
    final int data1 = packet[1];
    final int data2 = packet[2];

    final ByteData ts = packet.buffer.asByteData(
      packet.offsetInBytes + 3,
      8,
    );
    final int timestampUs = ts.getInt64(0, Endian.big);

    final int hi = status & 0xF0;
    final int channel = status & 0x0F;
    final MidiEventType type;
    final int pitch;
    final int velocity;
    final int ctrlNum;
    final int ctrlVal;

    if (hi == 0x80 || hi == 0x90) {
      type = hi == 0x90 ? MidiEventType.noteOn : MidiEventType.noteOff;
      pitch = data1;
      velocity = data2;
      ctrlNum = 0;
      ctrlVal = 0;
    } else if (hi == 0xB0) {
      type = MidiEventType.controlChange;
      pitch = 0;
      velocity = 0;
      ctrlNum = data1;
      ctrlVal = data2;
    } else {
      type = MidiEventType.other;
      pitch = 0;
      velocity = 0;
      ctrlNum = 0;
      ctrlVal = 0;
    }

    return MidiEvent(
      type: type,
      channel: channel,
      pitch: pitch,
      velocity: velocity,
      controllerNumber: ctrlNum,
      controllerValue: ctrlVal,
      timestampUs: timestampUs,
    );
  }

  static String? _decodeUtf8(List<int> bytes) {
    try {
      return String.fromCharCodes(bytes);
    } on FormatException {
      return null;
    }
  }
}
