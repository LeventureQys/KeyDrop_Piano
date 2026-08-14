import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keydrop_piano/domain/exceptions/dk_exception.dart';
import 'package:keydrop_piano/domain/models/dk_score.dart';

const DkScore _sample = DkScore(
  dkVersion: '1.0',
  meta: DkMeta(
    title: '小星星',
    composer: '传统',
    sourceMidiSha256: 'abc123',
    bpmBase: 120,
    timeSignature: '4/4',
    keySignature: 'C',
    totalDurationMs: 4000,
  ),
  tracks: <DkTrack>[
    DkTrack(
      id: 'main',
      notes: <DkNote>[
        DkNote(t: 0, d: 400, pitch: 60, velocity: 80),
        DkNote(t: 500, d: 400, pitch: 62, velocity: 80),
        DkNote(t: 1000, d: 400, pitch: 64, velocity: 80),
      ],
    ),
    DkTrack(
      id: 'second',
      notes: <DkNote>[
        DkNote(t: 0, d: 400, pitch: 48, velocity: 70),
        DkNote(t: 1000, d: 400, pitch: 50, velocity: 70),
        DkNote(t: 2000, d: 400, pitch: 52, velocity: 70),
      ],
    ),
  ],
  tempoMap: <DkTempoEvent>[
    DkTempoEvent(t: 0, bpm: 120),
    DkTempoEvent(t: 2000, bpm: 100),
  ],
);

void main() {
  group('DkScore JSON', () {
    test('T1 round-trip 字段逐一相等', () {
      final DkScore decoded = DkScore.fromJsonString(_sample.toJsonString());
      expect(decoded, equals(_sample));
      expect(decoded.dkVersion, '1.0');
      expect(decoded.meta.title, '小星星');
      expect(decoded.tracks.length, 2);
      expect(decoded.tracks.first.notes.length, 3);
      expect(decoded.tempoMap.length, 2);
    });

    test('T2 toJson key 集合精确符合规范字段', () {
      final Map<String, dynamic> json = _sample.toJson();
      expect(json.keys.toSet(),
          <String>{'dkVersion', 'meta', 'tracks', 'tempoMap'});

      final Map<String, dynamic> meta = json['meta'] as Map<String, dynamic>;
      expect(
        meta.keys.toSet(),
        <String>{
          'title',
          'composer',
          'sourceMidiSha256',
          'bpmBase',
          'timeSignature',
          'keySignature',
          'totalDurationMs',
        },
      );

      final Map<String, dynamic> note0 =
          ((json['tracks'] as List<dynamic>).first
                  as Map<String, dynamic>)['notes']
              .first as Map<String, dynamic>;
      expect(
        note0.keys.toSet(),
        <String>{'t', 'd', 'pitch', 'velocity', 'hand', 'finger'},
      );

      final Map<String, dynamic> tempo0 =
          (json['tempoMap'] as List<dynamic>).first as Map<String, dynamic>;
      expect(tempo0.keys.toSet(), <String>{'t', 'bpm'});
    });

    test('T3 notes 乱序自动排序并触发一次 warning', () {
      final String raw = jsonEncode(<String, dynamic>{
        'dkVersion': '1.0',
        'meta': <String, dynamic>{
          'title': 't',
          'composer': 'c',
          'sourceMidiSha256': 's',
          'bpmBase': 120,
          'timeSignature': '4/4',
          'keySignature': 'C',
          'totalDurationMs': 2000,
        },
        'tracks': <dynamic>[
          <String, dynamic>{
            'id': 'main',
            'notes': <dynamic>[
              <String, dynamic>{
                't': 1000,
                'd': 100,
                'pitch': 64,
                'velocity': 80,
                'hand': null,
                'finger': null
              },
              <String, dynamic>{
                't': 0,
                'd': 100,
                'pitch': 60,
                'velocity': 80,
                'hand': null,
                'finger': null
              },
              <String, dynamic>{
                't': 500,
                'd': 100,
                'pitch': 62,
                'velocity': 80,
                'hand': null,
                'finger': null
              },
            ],
          },
        ],
        'tempoMap': <dynamic>[
          <String, dynamic>{'t': 0, 'bpm': 120},
        ],
      });

      var warnCount = 0;
      final DkScore decoded = DkScore.fromJsonString(
        raw,
        onWarning: (String _) => warnCount++,
      );
      final List<int> ts =
          decoded.tracks.first.notes.map((DkNote n) => n.t).toList();
      expect(ts, <int>[0, 500, 1000]);
      expect(warnCount, 1);
    });

    test('T4 时间字段为 int，bpm 为 double', () {
      final DkScore decoded = DkScore.fromJsonString(_sample.toJsonString());
      expect(decoded.tracks.first.notes.first.t, isA<int>());
      expect(decoded.tracks.first.notes.first.d, isA<int>());
      expect(decoded.meta.totalDurationMs, isA<int>());
      expect(decoded.tempoMap.first.bpm, isA<double>());
    });

    test('T5 版本过高抛 DkVersionTooHighException', () {
      final String raw = _sample.toJsonString().replaceFirst('"1.0"', '"2.0"');
      expect(
        () => DkScore.fromJsonString(raw),
        throwsA(isA<DkVersionTooHighException>()),
      );
    });

    test('T6 版本过低占位升级，不抛异常并触发 warning', () {
      final String raw = _sample.toJsonString().replaceFirst('"1.0"', '"0.9"');
      var warnCount = 0;
      final DkScore decoded =
          DkScore.fromJsonString(raw, onWarning: (String _) => warnCount++);
      expect(decoded.dkVersion, '0.9');
      expect(warnCount, greaterThanOrEqualTo(1));
    });

    test('T7 null hand/finger round-trip 且 JSON 含 "hand": null', () {
      final DkScore decoded = DkScore.fromJsonString(_sample.toJsonString());
      expect(decoded.tracks.first.notes.first.hand, isNull);
      expect(decoded.tracks.first.notes.first.finger, isNull);

      final Map<String, dynamic> noteJson =
          _sample.tracks.first.notes.first.toJson();
      expect(noteJson.containsKey('hand'), isTrue);
      expect(noteJson['hand'], isNull);
      expect(noteJson.containsKey('finger'), isTrue);
      expect(noteJson['finger'], isNull);
    });

    test('T8 相等性：同值对象 == 且 hashCode 一致，异值不相等', () {
      final DkScore a = DkScore.fromJsonString(_sample.toJsonString());
      final DkScore b = DkScore.fromJsonString(_sample.toJsonString());
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);

      // tempoMap 不同 → 不相等
      final DkScore c = DkScore.fromJsonString(_sample
          .toJsonString()
          .replaceFirst('"bpm": 120', '"bpm": 90'));
      expect(a, isNot(equals(c)));

      // DkNote 单字段不同 → 不相等
      const DkNote n1 = DkNote(t: 0, d: 100, pitch: 60, velocity: 80);
      const DkNote n2 = DkNote(t: 0, d: 100, pitch: 60, velocity: 90);
      const DkNote n3 = DkNote(t: 0, d: 100, pitch: 60, velocity: 80);
      expect(n1, isNot(equals(n2)));
      expect(n1, equals(n3));
      expect(n1.hashCode, n3.hashCode);

      // DkTempoEvent 相等性
      const DkTempoEvent e1 = DkTempoEvent(t: 0, bpm: 120);
      const DkTempoEvent e2 = DkTempoEvent(t: 0, bpm: 120);
      const DkTempoEvent e3 = DkTempoEvent(t: 0, bpm: 100);
      expect(e1, equals(e2));
      expect(e1.hashCode, e2.hashCode);
      expect(e1, isNot(equals(e3)));

      // DkTrack 不同 id → 不相等
      const DkTrack t1 = DkTrack(id: 'main', notes: <DkNote>[n1]);
      const DkTrack t2 = DkTrack(id: 'other', notes: <DkNote>[n1]);
      expect(t1, isNot(equals(t2)));
    });

    test('T9 异常版本号解析：非法/缺 minor 不崩溃', () {
      // 无 minor（"1"）→ 合法，不抛不告警。
      final String raw1 = _sample.toJsonString().replaceFirst('"1.0"', '"1"');
      var warn1 = 0;
      final DkScore d1 =
          DkScore.fromJsonString(raw1, onWarning: (String _) => warn1++);
      expect(d1.dkVersion, '1');
      expect(warn1, 0);

      // 非数字（"abc"）→ 解析为 0 → 走占位升级告警，不崩溃。
      final String raw2 =
          _sample.toJsonString().replaceFirst('"1.0"', '"abc"');
      var warn2 = 0;
      final DkScore d2 =
          DkScore.fromJsonString(raw2, onWarning: (String _) => warn2++);
      expect(d2.dkVersion, 'abc');
      expect(warn2, greaterThanOrEqualTo(1));
    });

    test('T10 DkMeta 相等性与 indented 输出', () {
      const DkMeta m1 = DkMeta(
        title: 't',
        composer: 'c',
        sourceMidiSha256: 's',
        bpmBase: 120,
        timeSignature: '4/4',
        keySignature: 'C',
        totalDurationMs: 1000,
      );
      const DkMeta m2 = DkMeta(
        title: 't',
        composer: 'c',
        sourceMidiSha256: 's',
        bpmBase: 120,
        timeSignature: '4/4',
        keySignature: 'C',
        totalDurationMs: 1000,
      );
      const DkMeta m3 = DkMeta(
        title: 'x',
        composer: 'c',
        sourceMidiSha256: 's',
        bpmBase: 120,
        timeSignature: '4/4',
        keySignature: 'C',
        totalDurationMs: 1000,
      );
      expect(m1, equals(m2));
      expect(m1.hashCode, m2.hashCode);
      expect(m1, isNot(equals(m3)));

      final String pretty = _sample.toJsonString();
      expect(pretty, contains('\n'));
      expect(pretty, contains('  "dkVersion": "1.0"'));
    });
  });
}
