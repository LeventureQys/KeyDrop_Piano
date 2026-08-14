import 'package:flutter_test/flutter_test.dart';
import 'package:keydrop_piano/domain/models/app_config.dart';
import 'package:keydrop_piano/domain/models/dk_score.dart';
import 'package:keydrop_piano/domain/services/judgment_engine.dart';
import 'package:keydrop_piano/domain/services/statistics_aggregator.dart';

DkScore _score(List<DkNote> notes) => DkScore(
      dkVersion: '1.0',
      meta: const DkMeta(
        title: '小星星',
        composer: '传统',
        sourceMidiSha256: 'abc123',
        bpmBase: 120,
        timeSignature: '4/4',
        keySignature: 'C',
        totalDurationMs: 4000,
      ),
      tracks: <DkTrack>[
        DkTrack(id: 'main', notes: notes),
      ],
      tempoMap: <DkTempoEvent>[
        const DkTempoEvent(t: 0, bpm: 120),
      ],
    );

final DkScore _sample = _score(<DkNote>[
  const DkNote(t: 0, d: 400, pitch: 60, velocity: 80),
  const DkNote(t: 500, d: 400, pitch: 62, velocity: 80),
  const DkNote(t: 1000, d: 400, pitch: 64, velocity: 80),
]);

void main() {
  group('JudgmentEngine 基础判定', () {
    test('学习模式 - 全部按对', () {
      final JudgmentEngine engine = JudgmentEngine(
        score: _sample,
        width: JudgmentWidth.wide,
        latencyOffset: 0,
        learningMode: true,
      );
      final JudgmentRecord? r0 = engine.onKeyPress(60, 0);
      expect(r0, isNotNull);
      expect(r0!.result, JudgmentResult.perfect);

      final JudgmentRecord? r1 = engine.onKeyPress(62, 500);
      expect(r1, isNotNull);
      expect(r1!.result, JudgmentResult.perfect);

      final JudgmentRecord? r2 = engine.onKeyPress(64, 1000);
      expect(r2, isNotNull);
      expect(r2!.result, JudgmentResult.perfect);

      expect(engine.records.length, 3);
      expect(engine.allNotesJudged, isTrue);
    });

    test('演奏模式 - 掉 key 检查', () {
      final JudgmentEngine engine = JudgmentEngine(
        score: _sample,
        width: JudgmentWidth.wide,
        latencyOffset: 0,
      );
      final List<MissedNote> missed = engine.checkMissedNotes(1100);
      expect(missed.length, 3);
      expect(missed.first.note.pitch, 60);
      // 已判 miss 的 note 不会重复掉 key。
      expect(engine.checkMissedNotes(2000), isEmpty);
    });

    test('抢拍判定', () {
      final JudgmentEngine engine = JudgmentEngine(
        score: _sample,
        width: JudgmentWidth.wide,
        latencyOffset: 0,
      );
      final JudgmentRecord? r = engine.onKeyPress(60, -50);
      expect(r, isNotNull);
      expect(r!.result, JudgmentResult.early);
    });

    test('拖拍判定', () {
      final JudgmentEngine engine = JudgmentEngine(
        score: _sample,
        width: JudgmentWidth.wide,
        latencyOffset: 0,
      );
      final JudgmentRecord? r = engine.onKeyPress(62, 570);
      expect(r, isNotNull);
      expect(r!.result, JudgmentResult.late);
    });

    test('错音（按了不在谱中的键）', () {
      final JudgmentEngine engine = JudgmentEngine(
        score: _sample,
        width: JudgmentWidth.wide,
        latencyOffset: 0,
      );
      final JudgmentRecord? r = engine.onKeyPress(99, 500);
      expect(r, isNull);
      expect(engine.errorCount, 1);
    });

    test('computeStats 汇总正确', () {
      final JudgmentEngine engine = JudgmentEngine(
        score: _sample,
        width: JudgmentWidth.wide,
        latencyOffset: 0,
      );
      engine.onKeyPress(60, 0); // perfect
      engine.onKeyPress(62, 570); // late
      engine.onKeyPress(99, 500); // error

      final JudgmentStats s = computeStats(engine.records, engine.errorCount);
      expect(s.perfect, 1);
      expect(s.late, 1);
      expect(s.error, 1);
      expect(s.early, 0);
      expect(s.miss, 0);
    });

    test('计分公式：完美100/抢拖70/掉错0', () {
      final JudgmentStats s = JudgmentStats()
        ..perfect = 4
        ..early = 2
        ..late = 2
        ..miss = 1
        ..error = 1;
      // (4*100 + 2*70 + 2*70 + 1*0 + 1*0) / 10 = 68.0
      expect(s.scorePercent, closeTo(68.0, 0.001));
    });
  });

  group('判定窗口（Version 3.2 表）', () {
    test('strict = ±15 完美 / ±30 掉', () {
      final JudgmentEngine engine = JudgmentEngine(
        score: _sample,
        width: JudgmentWidth.strict,
        latencyOffset: 0,
      );
      expect(engine.onKeyPress(60, 10)!.result, JudgmentResult.perfect);
      // delta = 475 - 500 = -25 → 15 < |25| ≤ 30 抢拍窗。
      expect(engine.onKeyPress(62, 475)!.result, JudgmentResult.early);
      // 剩 note 64（t=1000）未判 → 掉 key。
      final List<MissedNote> missed = engine.checkMissedNotes(2000);
      expect(missed.length, 1);
      expect(missed.first.note.pitch, 64);
    });

    test('medium = ±25 完美 / ±50 掉', () {
      final JudgmentEngine engine = JudgmentEngine(
        score: _sample,
        width: JudgmentWidth.medium,
        latencyOffset: 0,
      );
      expect(engine.onKeyPress(60, 20)!.result, JudgmentResult.perfect);
      final JudgmentRecord? r = engine.onKeyPress(62, 540);
      expect(r, isNotNull);
      expect(r!.result, JudgmentResult.late); // +40 在 25-50 拖拍区间
    });
  });

  group('延迟补偿公式（Version 3.2：按下 - (触底 + offset)）', () {
    test('offset=+50 时，在 t+50 按下判 perfect', () {
      final JudgmentEngine engine = JudgmentEngine(
        score: _sample,
        width: JudgmentWidth.wide,
        latencyOffset: 50,
      );
      final JudgmentRecord? r = engine.onKeyPress(62, 550);
      expect(r, isNotNull);
      expect(r!.result, JudgmentResult.perfect);
    });

    test('offset=+50 时，在 t 按下判 early（早于补偿线）', () {
      final JudgmentEngine engine = JudgmentEngine(
        score: _sample,
        width: JudgmentWidth.wide,
        latencyOffset: 50,
      );
      final JudgmentRecord? r = engine.onKeyPress(62, 500);
      expect(r, isNotNull);
      expect(r!.result, JudgmentResult.early);
    });

    test('offset=-40 时，在 t-40 按下判 perfect', () {
      final JudgmentEngine engine = JudgmentEngine(
        score: _sample,
        width: JudgmentWidth.wide,
        latencyOffset: -40,
      );
      final JudgmentRecord? r = engine.onKeyPress(62, 460);
      expect(r, isNotNull);
      expect(r!.result, JudgmentResult.perfect);
    });
  });

  group('和弦判定（F4）', () {
    final DkScore chord = _score(<DkNote>[
      const DkNote(t: 1000, d: 400, pitch: 60, velocity: 80),
      const DkNote(t: 1000, d: 400, pitch: 64, velocity: 90),
      const DkNote(t: 1000, d: 400, pitch: 67, velocity: 85),
    ]);

    test('同 t 不同 pitch 独立判定，互不吞键', () {
      final JudgmentEngine engine = JudgmentEngine(
        score: chord,
        width: JudgmentWidth.wide,
        latencyOffset: 0,
      );
      final JudgmentRecord? r0 = engine.onKeyPress(60, 1000);
      expect(r0, isNotNull);
      expect(r0!.result, JudgmentResult.perfect);
      // 和弦尚未完成：还有到期未判定 note。
      expect(engine.hasDueUnjudgedNotes(1000), isTrue);
      final JudgmentRecord? r1 = engine.onKeyPress(64, 1000);
      expect(r1, isNotNull);
      final JudgmentRecord? r2 = engine.onKeyPress(67, 1000);
      expect(r2, isNotNull);
      expect(engine.allNotesJudged, isTrue);
      expect(engine.records.length, 3);
    });

    test('缺一键 → 演奏模式该键掉 key', () {
      final JudgmentEngine engine = JudgmentEngine(
        score: chord,
        width: JudgmentWidth.wide,
        latencyOffset: 0,
      );
      engine.onKeyPress(60, 1000);
      engine.onKeyPress(64, 1000);
      final List<MissedNote> missed = engine.checkMissedNotes(1200);
      expect(missed.length, 1);
      expect(missed.first.note.pitch, 67);
    });
  });

  group('学习模式语义（F1：key 等用户）', () {
    test('到期后无时间上限：很久之后按下仍判为 late（不 miss）', () {
      final JudgmentEngine engine = JudgmentEngine(
        score: _sample,
        width: JudgmentWidth.wide,
        latencyOffset: 0,
        learningMode: true,
      );
      final JudgmentRecord? r = engine.onKeyPress(62, 9000);
      expect(r, isNotNull);
      expect(r!.result, isNot(JudgmentResult.miss));
      expect(r.result, JudgmentResult.late);
    });

    test('过早按键不吞未来 note', () {
      final JudgmentEngine engine = JudgmentEngine(
        score: _sample,
        width: JudgmentWidth.wide,
        latencyOffset: 0,
        learningMode: true,
      );
      // note t=1000（pitch 64）还有 700ms 才到，此时按 64 不匹配 → 错音。
      final JudgmentRecord? r = engine.onKeyPress(64, 300);
      expect(r, isNull);
      expect(engine.errorCount, 1);
      // 到时间后正常判定。
      final JudgmentRecord? r2 = engine.onKeyPress(64, 1000);
      expect(r2, isNotNull);
      expect(r2!.result, JudgmentResult.perfect);
    });
  });
}
