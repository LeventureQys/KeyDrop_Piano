import 'dart:math';

import '../models/dk_score.dart';
import '../models/midi_data.dart';

/// 由 [MidiData] 生成 [DkScore]（Version D2 / Stage 3 设计文档 5）。
///
/// 纯 Dart，零平台依赖。不做自动旋律提取（用户手动指定旋律轨）。
class DkGenerator {
  /// 键盘可用范围 A0–C8。
  static const int _minPitch = 21;
  static const int _maxPitch = 108;

  /// 由 [data] 生成 DkScore。
  ///
  /// [melodyTrackIndex] 为 null = 合并所有轨道；非 null = 仅取该原始轨道。
  DkScore generate(
    MidiData data, {
    int? melodyTrackIndex,
    String title = '',
    String composer = '',
    String sourceMidiSha256 = '',
  }) {
    final Iterable<MidiNoteEvent> source = melodyTrackIndex == null
        ? data.notes
        : data.notes
            .where((MidiNoteEvent n) => n.trackIndex == melodyTrackIndex);

    // 去重：同 (startMs, pitch) 合并，velocity 取最大、duration 取最长。
    final Map<int, _Agg> agg = <int, _Agg>{};
    for (final MidiNoteEvent n in source) {
      if (n.pitch < _minPitch || n.pitch > _maxPitch) {
        continue;
      }
      final int key = (n.startMs << 7) | n.pitch;
      final _Agg? existing = agg[key];
      if (existing == null) {
        agg[key] = _Agg(n.startMs, n.pitch, n.velocity, n.durationMs);
      } else {
        existing.velocity = max(existing.velocity, n.velocity);
        existing.durationMs = max(existing.durationMs, n.durationMs);
      }
    }

    final List<DkNote> notes = agg.values
        .map((_Agg a) => DkNote(
              t: a.startMs,
              d: a.durationMs,
              pitch: a.pitch,
              velocity: a.velocity,
            ))
        .toList();
    notes.sort((DkNote a, DkNote b) {
      final int byT = a.t.compareTo(b.t);
      return byT != 0 ? byT : a.pitch.compareTo(b.pitch);
    });

    final int bpmBase =
        data.tempoMap.isNotEmpty ? data.tempoMap.first.bpm.round() : 120;

    final DkMeta meta = DkMeta(
      title: title,
      composer: composer,
      sourceMidiSha256: sourceMidiSha256,
      bpmBase: bpmBase,
      timeSignature: data.timeSignature,
      keySignature: data.keySignature,
      totalDurationMs: data.totalDurationMs,
    );

    final List<DkTempoEvent> tempoMap = data.tempoMap
        .map((MidiTempoChange e) => DkTempoEvent(t: e.t, bpm: e.bpm))
        .toList();

    return DkScore(
      dkVersion: '1.0',
      meta: meta,
      tracks: <DkTrack>[DkTrack(id: 'main', notes: notes)],
      tempoMap: tempoMap,
    );
  }
}

class _Agg {
  _Agg(this.startMs, this.pitch, this.velocity, this.durationMs);
  final int startMs;
  final int pitch;
  int velocity;
  int durationMs;
}
