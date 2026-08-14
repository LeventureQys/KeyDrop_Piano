import 'package:flutter_test/flutter_test.dart';
import 'package:keydrop_piano/domain/models/dk_score.dart';
import 'package:keydrop_piano/domain/services/bpm_scaler.dart';

void main() {
  const BpmScaler scaler = BpmScaler();

  group('BpmScaler', () {
    test('倍率 1.0 恒等', () {
      expect(scaler.scaleElapsed(1000, 1.0), 1000);
    });

    test('倍率 2.0：播放时间线双倍速（V3 场景 E）', () {
      expect(scaler.scaleElapsed(1000, 2.0), 2000);
      // 原 t=2000 的事件在实际时间 1000ms 处发生。
      expect(scaler.scaleToElapsed(2000, 2.0), 1000);
    });

    test('倍率 0.5：半速', () {
      expect(scaler.scaleElapsed(1000, 0.5), 500);
    });

    test('bpmAt 取 t 之前最后一个 tempo 事件', () {
      const List<DkTempoEvent> tempoMap = <DkTempoEvent>[
        DkTempoEvent(t: 0, bpm: 120),
        DkTempoEvent(t: 5000, bpm: 90),
      ];
      expect(scaler.bpmAt(tempoMap, 0), 120);
      expect(scaler.bpmAt(tempoMap, 4999), 120);
      expect(scaler.bpmAt(tempoMap, 5000), 90);
      expect(scaler.bpmAt(tempoMap, 99999), 90);
    });

    test('bpmAt 空 tempoMap 回退 120', () {
      expect(scaler.bpmAt(const <DkTempoEvent>[], 0), 120);
    });

    test('barAt：120bpm 4/4 每 2000ms 一小节', () {
      expect(scaler.barAt(0, 120, 4), 1);
      expect(scaler.barAt(1999, 120, 4), 1);
      expect(scaler.barAt(2000, 120, 4), 2);
      expect(scaler.barAt(15999, 120, 4), 8);
    });

    test('totalBars：16000ms @120bpm 4/4 = 8 小节', () {
      const DkScore score = DkScore(
        dkVersion: '1.0',
        meta: DkMeta(
          title: '',
          composer: '',
          sourceMidiSha256: '',
          bpmBase: 120,
          timeSignature: '4/4',
          keySignature: 'C',
          totalDurationMs: 16000,
        ),
        tracks: <DkTrack>[],
        tempoMap: <DkTempoEvent>[],
      );
      expect(scaler.totalBars(score), 8);
    });
  });
}
