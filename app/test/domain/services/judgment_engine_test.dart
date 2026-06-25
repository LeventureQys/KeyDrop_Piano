import 'package:flutter_test/flutter_test.dart';
import 'package:keydrop_piano/domain/models/app_config.dart';
import 'package:keydrop_piano/domain/models/dk_score.dart';
import 'package:keydrop_piano/domain/services/judgment_engine.dart';

/// 复用自 dk_score_test.dart 的 _sample。
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
  ],
  tempoMap: <DkTempoEvent>[
    DkTempoEvent(t: 0, bpm: 120),
  ],
);

void main() {
  final DkScore score = _sample;

  group('JudgmentEngine', () {
    test('学习模式 - 全部按对', () {
      final JudgmentEngine engine = JudgmentEngine(
        score: score,
        width: JudgmentWidth.wide,
        latencyOffset: 0,
      );
      // 按对 3 个 note（t=0,500,1000）
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
    });

    test('演奏模式 - 掉 key 检查', () {
      final JudgmentEngine engine = JudgmentEngine(
        score: score,
        width: JudgmentWidth.wide,
        latencyOffset: 0,
      );
      // 不按键，让时间走到 1090ms（超过 1000+80=1080ms 的 deadline）
      final List<MissedNote> missed = engine.checkMissedNotes(1100);
      expect(missed.length, greaterThan(0));
    });

    test('抢拍判定', () {
      final JudgmentEngine engine = JudgmentEngine(
        score: score,
        width: JudgmentWidth.wide,
        latencyOffset: 0,
      );
      // note 在 t=0，用户在 -50ms 按（抢拍）
      final JudgmentRecord? r = engine.onKeyPress(60, -50);
      expect(r, isNotNull);
      expect(r!.result, JudgmentResult.early);
    });

    test('拖拍判定', () {
      final JudgmentEngine engine = JudgmentEngine(
        score: score,
        width: JudgmentWidth.wide,
        latencyOffset: 0,
      );
      // note 在 t=500，用户在 570ms 按（拖拍）
      final JudgmentRecord? r = engine.onKeyPress(62, 570);
      expect(r, isNotNull);
      expect(r!.result, JudgmentResult.late);
    });

    test('错音（按了不在谱中的键）', () {
      final JudgmentEngine engine = JudgmentEngine(
        score: score,
        width: JudgmentWidth.wide,
        latencyOffset: 0,
      );
      // pitch 99 不在谱中
      final JudgmentRecord? r = engine.onKeyPress(99, 500);
      expect(r, isNull);
    });

    test('computeStats 汇总正确', () {
      final JudgmentEngine engine = JudgmentEngine(
        score: score,
        width: JudgmentWidth.wide,
        latencyOffset: 0,
      );
      engine.onKeyPress(60, 0); // perfect
      engine.onKeyPress(62, 570); // late
      engine.onKeyPress(99, 500); // error

      final JudgmentStats s = computeStats(engine.records, 1);
      expect(s.perfect, 1);
      expect(s.late, 1);
      expect(s.error, 1);
      expect(s.early, 0);
      expect(s.miss, 0);
    });
  });
}
