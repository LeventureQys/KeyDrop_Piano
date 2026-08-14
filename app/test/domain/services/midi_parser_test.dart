import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:keydrop_piano/domain/exceptions/dk_exception.dart';
import 'package:keydrop_piano/domain/models/midi_data.dart';
import 'package:keydrop_piano/domain/services/midi_parser.dart';

Uint8List _readFixture(String name) =>
    File('test/fixtures/$name').readAsBytesSync();

List<int> _u32(int v) =>
    <int>[(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF];
List<int> _u16(int v) => <int>[(v >> 8) & 0xFF, v & 0xFF];
List<int> _mthd(int fmt, int ntrks) => <int>[
      ...'MThd'.codeUnits,
      ..._u32(6),
      ..._u16(fmt),
      ..._u16(ntrks),
      ..._u16(480),
    ];
List<int> _mtrk(List<int> body) =>
    <int>[...'MTrk'.codeUnits, ..._u32(body.length), ...body];
Uint8List _file(List<int> a, List<int> b) => Uint8List.fromList(<int>[...a, ...b]);

void main() {
  final MidiParser parser = MidiParser();

  group('MidiParser fixtures', () {
    test('M1 格式0 C 大调音阶 8 音、间隔约 500ms', () {
      final MidiData d = parser.parse(_readFixture('f0_cmajor_scale.mid'));
      expect(d.format, MidiFormat.single);
      expect(d.notes.length, 8);
      expect(d.notes.map((MidiNoteEvent n) => n.pitch).toList(),
          <int>[60, 62, 64, 65, 67, 69, 71, 72]);
      expect(d.notes[0].startMs, 0);
      expect(d.notes[1].startMs, closeTo(500, 2));
      expect(d.notes[2].startMs, closeTo(1000, 2));
      expect(d.totalDurationMs, greaterThan(0));
    });

    test('M2 格式1 双轨合并、track 信息含名称', () {
      final MidiData d = parser.parse(_readFixture('f1_two_tracks.mid'));
      expect(d.format, MidiFormat.multiTrack);
      expect(d.tracks.length, 2);
      expect(d.tracks[0].trackName, 'Melody');
      expect(d.tracks[1].trackName, 'Bass');
      expect(d.notes.length, 8);
      for (var i = 1; i < d.notes.length; i++) {
        expect(d.notes[i].startMs, greaterThanOrEqualTo(d.notes[i - 1].startMs));
      }
    });

    test('M3 tempo 变化：两段 tempo、后段间隔变大', () {
      final MidiData d = parser.parse(_readFixture('f1_tempo_change.mid'));
      expect(d.tempoMap.length, 2);
      expect(d.tempoMap[0].bpm, closeTo(120, 1));
      expect(d.tempoMap[1].bpm, closeTo(90, 1));
      final int earlyGap = d.notes[1].startMs - d.notes[0].startMs;
      final int lateGap = d.notes[5].startMs - d.notes[4].startMs;
      expect(lateGap, greaterThan(earlyGap));
    });

    test('M4 拍号 3/4、调号 G', () {
      final MidiData d = parser.parse(_readFixture('f1_timesig_keysig.mid'));
      expect(d.timeSignature, '3/4');
      expect(d.keySignature, 'G');
      expect(d.notes, isNotEmpty);
    });

    test('M5 格式2 抛 UnsupportedMidiFormatException', () {
      expect(
        () => parser.parse(_readFixture('format2.mid')),
        throwsA(isA<UnsupportedMidiFormatException>()),
      );
    });

    test('M6 损坏文件抛 CorruptedMidiException', () {
      expect(
        () => parser.parse(_readFixture('corrupted.mid')),
        throwsA(isA<CorruptedMidiException>()),
      );
    });
  });

  group('MidiParser inline 字节', () {
    test('M7 running status：省略状态字节的连续 noteOn', () {
      final List<int> body = <int>[
        0x00, 0x90, 60, 0x64, // noteOn p60
        0x00, 62, 0x64, // running status → noteOn p62
        0x83, 0x60, 0x80, 60, 0x40, // delta480 noteOff p60
        0x00, 0x80, 62, 0x40, // noteOff p62
        0x00, 0xFF, 0x2F, 0x00, // end of track
      ];
      final MidiData d = parser.parse(_file(_mthd(0, 1), _mtrk(body)));
      expect(d.notes.length, 2);
      expect(d.notes.map((MidiNoteEvent n) => n.pitch).toSet(), <int>{60, 62});
    });

    test('M8 noteOn velocity 0 视为 noteOff', () {
      final List<int> body = <int>[
        0x00, 0x90, 60, 0x64, // noteOn
        0x83, 0x60, 0x90, 60, 0x00, // delta480 noteOn vel0 = noteOff
        0x00, 0xFF, 0x2F, 0x00,
      ];
      final MidiData d = parser.parse(_file(_mthd(0, 1), _mtrk(body)));
      expect(d.notes.length, 1);
      expect(d.notes.first.durationMs, closeTo(500, 2));
    });

    test('空 note 文件抛 UnsupportedMidiFormatException', () {
      final List<int> body = <int>[
        0x00, 0xFF, 0x51, 0x03, 0x07, 0xA1, 0x20, // tempo 500000
        0x00, 0xFF, 0x2F, 0x00,
      ];
      expect(
        () => parser.parse(_file(_mthd(0, 1), _mtrk(body))),
        throwsA(isA<UnsupportedMidiFormatException>()),
      );
    });
  });

  group('不支持/损坏文案契约（Stage 3 不支持文件处理.md U1-U4/C1-C6）', () {
    String messageOf(void Function() body) {
      try {
        body();
      } on DkException catch (e) {
        return e.message;
      }
      fail('expected DkException');
    }

    test('U1 格式 2', () {
      expect(
        messageOf(() => parser.parse(_readFixture('format2.mid'))),
        '此文件为 SMF 格式 2，v1.0.0 仅支持格式 0/1。',
      );
    });

    test('U2 SMPTE 时基', () {
      final Uint8List f = _file(_mthd(0, 1), _mtrk(<int>[0, 0xFF, 0x2F, 0]));
      // 替换 division 为 SMPTE（最高位 1）。
      f[12] = 0xE8;
      f[13] = 0x28;
      expect(messageOf(() => parser.parse(f)), '此文件使用 SMPTE 时基，暂不支持。');
    });

    test('U3 未知格式', () {
      final Uint8List f = _file(_mthd(3, 1), _mtrk(<int>[0, 0xFF, 0x2F, 0]));
      expect(messageOf(() => parser.parse(f)), '未知的 SMF 格式 (3)。');
    });

    test('U4 无可演奏音符', () {
      final List<int> body = <int>[0x00, 0xFF, 0x2F, 0x00];
      expect(
        messageOf(() => parser.parse(_file(_mthd(0, 1), _mtrk(body)))),
        '未在文件中找到可演奏的音符。',
      );
    });

    test('C1 MThd 魔数损坏', () {
      expect(
        messageOf(() => parser.parse(_readFixture('corrupted.mid'))),
        '文件已损坏：在 chunk header 处读取失败。',
      );
    });

    test('C2 MThd 长度字段异常', () {
      final Uint8List f = Uint8List.fromList(<int>[
        ...'MThd'.codeUnits,
        0, 0, 0, 7, // 长度 7 ≠ 6
        0, 1, 0, 1, 1, 0xE0,
      ]);
      expect(
        messageOf(() => parser.parse(f)),
        startsWith('文件已损坏：MThd 长度字段异常'),
      );
    });

    test('C5 running status 缺失', () {
      final List<int> body = <int>[
        0x00, 60, 0x64, // 无状态字节且无 running status
        0x00, 0xFF, 0x2F, 0x00,
      ];
      expect(
        messageOf(() => parser.parse(_file(_mthd(0, 1), _mtrk(body)))),
        '文件已损坏：running status 缺失。',
      );
    });
  });
}
