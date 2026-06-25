import 'package:flutter_test/flutter_test.dart';
import 'package:keydrop_piano/domain/models/dk_score.dart';
import 'package:keydrop_piano/domain/models/midi_data.dart';
import 'package:keydrop_piano/domain/services/dk_generator.dart';

MidiNoteEvent _n(
  int track,
  int start,
  int pitch,
  int vel, {
  int dur = 400,
  int ch = 0,
}) =>
    MidiNoteEvent(
      trackIndex: track,
      channel: ch,
      startMs: start,
      durationMs: dur,
      pitch: pitch,
      velocity: vel,
    );

MidiData _data(
  List<MidiNoteEvent> notes, {
  List<MidiTempoChange> tempo = const <MidiTempoChange>[MidiTempoChange(0, 120)],
  String ts = '4/4',
  String ks = 'C',
  int total = 1000,
}) =>
    MidiData(
      format: MidiFormat.single,
      ticksPerQuarter: 480,
      notes: notes,
      tempoMap: tempo,
      timeSignature: ts,
      keySignature: ks,
      totalDurationMs: total,
      tracks: const <MidiTrackInfo>[],
    );

void main() {
  final DkGenerator gen = DkGenerator();

  test('G1 同 (t,pitch) 去重，velocity 取最大、duration 取最长', () {
    final DkScore s = gen.generate(_data(<MidiNoteEvent>[
      _n(0, 0, 60, 80, dur: 400),
      _n(0, 0, 60, 100, dur: 500),
    ]));
    expect(s.tracks.single.notes.length, 1);
    expect(s.tracks.single.notes.first.velocity, 100);
    expect(s.tracks.single.notes.first.d, 500);
  });

  test('G2 指定 melodyTrackIndex 仅含该轨', () {
    final DkScore s = gen.generate(
      _data(<MidiNoteEvent>[
        _n(0, 0, 60, 80),
        _n(1, 0, 48, 80),
        _n(1, 500, 50, 80),
      ]),
      melodyTrackIndex: 1,
    );
    expect(s.tracks.single.notes.length, 2);
    expect(
      s.tracks.single.notes.map((DkNote n) => n.pitch).toSet(),
      <int>{48, 50},
    );
  });

  test('G3 键盘范围外 pitch 被过滤', () {
    final DkScore s = gen.generate(_data(<MidiNoteEvent>[
      _n(0, 0, 10, 80), // < 21 过滤
      _n(0, 100, 120, 80), // > 108 过滤
      _n(0, 200, 60, 80), // 保留
    ]));
    expect(s.tracks.single.notes.length, 1);
    expect(s.tracks.single.notes.first.pitch, 60);
  });

  test('G4 meta 字段正确', () {
    final DkScore s = gen.generate(
      _data(
        <MidiNoteEvent>[_n(0, 0, 60, 80)],
        tempo: const <MidiTempoChange>[MidiTempoChange(0, 90)],
        ts: '3/4',
        ks: 'G',
        total: 12345,
      ),
      title: '小星星',
      composer: '传统',
      sourceMidiSha256: 'deadbeef',
    );
    expect(s.meta.title, '小星星');
    expect(s.meta.composer, '传统');
    expect(s.meta.sourceMidiSha256, 'deadbeef');
    expect(s.meta.bpmBase, 90);
    expect(s.meta.timeSignature, '3/4');
    expect(s.meta.keySignature, 'G');
    expect(s.meta.totalDurationMs, 12345);
  });

  test('G5 生成结果可 round-trip', () {
    final DkScore s = gen.generate(_data(<MidiNoteEvent>[
      _n(0, 0, 60, 80),
      _n(0, 500, 62, 80),
      _n(0, 1000, 64, 80),
    ]));
    final DkScore back = DkScore.fromJsonString(s.toJsonString());
    expect(back, equals(s));
  });

  test('G6 单轨 main、升序、dkVersion 1.0、hand/finger 均 null', () {
    final DkScore s = gen.generate(_data(<MidiNoteEvent>[
      _n(0, 1000, 64, 80),
      _n(0, 0, 60, 80),
      _n(0, 500, 62, 80),
    ]));
    expect(s.dkVersion, '1.0');
    expect(s.tracks.single.id, 'main');
    final List<int> ts = s.tracks.single.notes.map((DkNote n) => n.t).toList();
    final List<int> sorted = <int>[...ts]..sort();
    expect(ts, sorted);
    for (final DkNote n in s.tracks.single.notes) {
      expect(n.hand, isNull);
      expect(n.finger, isNull);
    }
  });
}
