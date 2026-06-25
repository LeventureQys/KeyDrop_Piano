import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:keydrop_piano/domain/ports/midi_input_port.dart';
import 'package:keydrop_piano/platform/android/android_midi_input_adapter.dart';

List<int> _buildPacket(int status, int data1, int data2, int timestampUs) {
  final ByteData bd =
      ByteData(11);
  bd.setUint8(0, status);
  bd.setUint8(1, data1);
  bd.setUint8(2, data2);
  bd.setInt64(3, timestampUs, Endian.big);
  return bd.buffer.asUint8List();
}

void main() {
  group('decodeMidiPacket', () {
    test('noteOn', () {
      final Uint8List packet =
          Uint8List.fromList(_buildPacket(0x90, 60, 0x64, 12345678));
      final MidiEvent? e = AndroidMidiInputAdapter.decodeMidiPacket(packet);
      expect(e, isNotNull);
      expect(e!.type, MidiEventType.noteOn);
      expect(e.channel, 0);
      expect(e.pitch, 60);
      expect(e.velocity, 0x64);
      expect(e.timestampUs, 12345678);
    });

    test('noteOff', () {
      final Uint8List packet =
          Uint8List.fromList(_buildPacket(0x80, 72, 0x40, 0));
      final MidiEvent? e = AndroidMidiInputAdapter.decodeMidiPacket(packet);
      expect(e, isNotNull);
      expect(e!.type, MidiEventType.noteOff);
      expect(e.channel, 0);
      expect(e.pitch, 72);
      expect(e.velocity, 0x40);
    });

    test('controlChange CC64', () {
      final Uint8List packet =
          Uint8List.fromList(_buildPacket(0xB0, 64, 127, 0));
      final MidiEvent? e = AndroidMidiInputAdapter.decodeMidiPacket(packet);
      expect(e, isNotNull);
      expect(e!.type, MidiEventType.controlChange);
      expect(e.controllerNumber, 64);
      expect(e.controllerValue, 127);
    });

    test('other type', () {
      final Uint8List packet =
          Uint8List.fromList(_buildPacket(0xE0, 0, 0, 0));
      final MidiEvent? e = AndroidMidiInputAdapter.decodeMidiPacket(packet);
      expect(e, isNotNull);
      expect(e!.type, MidiEventType.other);
    });

    test('null on short packet', () {
      final Uint8List short = Uint8List(5);
      expect(
        AndroidMidiInputAdapter.decodeMidiPacket(short),
        isNull,
      );
    });
  });

  group('splitMidiPackets', () {
    test('splits 33 bytes into 3 packets of 11', () {
      final Uint8List data = Uint8List.fromList(
        <int>[
          ..._buildPacket(0x90, 60, 0x64, 1),
          ..._buildPacket(0x90, 62, 0x64, 2),
          ..._buildPacket(0x80, 60, 0x40, 3),
        ],
      );
      final List<Uint8List> packets =
          AndroidMidiInputAdapter.splitMidiPackets(data);
      expect(packets.length, 3);
      expect(packets[0].length, 11);
    });

    test('ignores trailing partial bytes', () {
      final Uint8List data = Uint8List.fromList(
        <int>[..._buildPacket(0x90, 60, 0x64, 1), 0, 0, 0],
      );
      final List<Uint8List> packets =
          AndroidMidiInputAdapter.splitMidiPackets(data);
      expect(packets.length, 1);
    });
  });
}
