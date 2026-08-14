import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:keydrop_piano/domain/exceptions/dk_exception.dart';
import 'package:keydrop_piano/domain/models/dk_score.dart';
import 'package:keydrop_piano/domain/models/midi_data.dart';
import 'package:keydrop_piano/domain/services/dk_generator.dart';
import 'package:keydrop_piano/domain/services/midi_parser.dart';

/// Version 验收文档 2.3 命名 fixture 的解析/生成正确性测试，
/// 含 V3 场景 A 的 golden 对比（忽略空白后 byte-equal）。
void main() {
  Uint8List fixture(String name) =>
      File('test_fixtures/$name').readAsBytesSync();

  test('验收 fixture 全部存在', () {
    for (final String name in <String>[
      'simple_format0_8bars.mid',
      'simple_format1_2tracks.mid',
      'tempo_change.mid',
      'time_signature_3_4.mid',
      'corrupted.mid',
      'format2.mid',
      'golden_simple_format0_8bars.dk.json',
    ]) {
      expect(File('test_fixtures/$name').existsSync(), isTrue,
          reason: 'missing $name');
    }
  });

  test('V3-A：simple_format0_8bars.mid → DK 谱与 golden 一致（忽略空白）', () {
    final MidiData data = MidiParser().parse(fixture('simple_format0_8bars.mid'));
    expect(data.notes.length, 32);
    expect(data.totalDurationMs, greaterThanOrEqualTo(16000));

    final DkScore generated = DkGenerator().generate(data);
    final String golden =
        File('test_fixtures/golden_simple_format0_8bars.dk.json')
            .readAsStringSync();

    final String normalizedGolden =
        golden.replaceAll(RegExp(r'\s+'), '');
    final String normalizedGenerated =
        generated.toJsonString().replaceAll(RegExp(r'\s+'), '');
    expect(normalizedGenerated, normalizedGolden);
  });

  test('round-trip：golden 谱可反序列化且字段合法', () {
    final DkScore score = DkScore.fromJsonString(
        File('test_fixtures/golden_simple_format0_8bars.dk.json')
            .readAsStringSync());
    expect(score.dkVersion, '1.0');
    expect(score.tracks.single.id, 'main');
    expect(score.tracks.single.notes.length, 32);
    expect(score.meta.timeSignature, '4/4');
    expect(score.meta.bpmBase, 120);
    // 严格升序。
    for (var i = 1; i < score.tracks.single.notes.length; i++) {
      expect(
        score.tracks.single.notes[i].t,
        greaterThanOrEqualTo(score.tracks.single.notes[i - 1].t),
      );
    }
  });

  test('format2.mid 抛 UnsupportedMidiFormatException', () {
    expect(
      () => MidiParser().parse(fixture('format2.mid')),
      throwsA(isA<UnsupportedMidiFormatException>()),
    );
  });

  test('corrupted.mid 抛 CorruptedMidiException', () {
    expect(
      () => MidiParser().parse(fixture('corrupted.mid')),
      throwsA(isA<CorruptedMidiException>()),
    );
  });

  test('simple_format1_2tracks.mid：双轨可选旋律轨', () {
    final MidiData data =
        MidiParser().parse(fixture('simple_format1_2tracks.mid'));
    expect(data.format, MidiFormat.multiTrack);
    expect(data.tracks.length, 2);

    // 仅旋律轨（trackIndex 0）。
    final DkScore melody =
        DkGenerator().generate(data, melodyTrackIndex: 0);
    expect(melody.tracks.single.notes.length, 4);
    expect(melody.tracks.single.notes.map((DkNote n) => n.pitch),
        <int>[60, 62, 64, 65]);
  });

  test('tempo_change.mid：tempoMap 两段且后段间隔变大', () {
    final MidiData data = MidiParser().parse(fixture('tempo_change.mid'));
    expect(data.tempoMap.length, 2);
    expect(data.tempoMap[1].bpm, closeTo(90, 1));
    final int earlyGap = data.notes[1].startMs - data.notes[0].startMs;
    final int lateGap = data.notes[5].startMs - data.notes[4].startMs;
    expect(lateGap, greaterThan(earlyGap));
  });

  test('time_signature_3_4.mid：3/4 与 G 大调', () {
    final MidiData data =
        MidiParser().parse(fixture('time_signature_3_4.mid'));
    expect(data.timeSignature, '3/4');
    expect(data.keySignature, 'G');
  });
}
