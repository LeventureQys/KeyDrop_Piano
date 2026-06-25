import 'package:meta/meta.dart';

/// 解析后的 MIDI 格式（格式 2 不入此枚举，解析时直接抛异常）。
enum MidiFormat { single, multiTrack }

/// `MidiParser` 输出的中间模型（领域内部用，不直接序列化）。
@immutable
class MidiData {
  const MidiData({
    required this.format,
    required this.ticksPerQuarter,
    required this.notes,
    required this.tempoMap,
    required this.timeSignature,
    required this.keySignature,
    required this.totalDurationMs,
    required this.tracks,
  });

  final MidiFormat format;
  final int ticksPerQuarter;

  /// 已合并所有轨道、已转换为毫秒、按 startMs 升序。
  final List<MidiNoteEvent> notes;

  /// 至少含 t=0 的初始 tempo。
  final List<MidiTempoChange> tempoMap;
  final String timeSignature;
  final String keySignature;
  final int totalDurationMs;

  /// 每个原始轨道的统计（供转换页选旋律轨）。
  final List<MidiTrackInfo> tracks;
}

@immutable
class MidiNoteEvent {
  const MidiNoteEvent({
    required this.trackIndex,
    required this.channel,
    required this.startMs,
    required this.durationMs,
    required this.pitch,
    required this.velocity,
  });

  final int trackIndex;
  final int channel;
  final int startMs;
  final int durationMs;
  final int pitch;
  final int velocity;
}

@immutable
class MidiTempoChange {
  const MidiTempoChange(this.t, this.bpm);

  /// 毫秒。
  final int t;
  final double bpm;
}

@immutable
class MidiTrackInfo {
  const MidiTrackInfo({
    required this.trackIndex,
    required this.channel,
    required this.noteCount,
    required this.minPitch,
    required this.maxPitch,
    required this.trackName,
  });

  final int trackIndex;

  /// 该轨主通道（首个 note 的 channel；无 note 则 -1）。
  final int channel;
  final int noteCount;

  /// 无 note 时 -1。
  final int minPitch;

  /// 无 note 时 -1。
  final int maxPitch;
  final String? trackName;
}
