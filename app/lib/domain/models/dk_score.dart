import 'dart:convert';

import 'package:meta/meta.dart';

import '../exceptions/dk_exception.dart';

/// DK 谱模型（Version 设计文档 3.1）。
///
/// 序列化规则（强制）：
/// - 字段名严格 camelCase、大小写敏感。
/// - 时间字段（t/d/totalDurationMs）一律 int 毫秒；bpm 为 double。
/// - notes 反序列化后按 t 升序；乱序时排序并触发 onWarning。
/// - dkVersion 主版本 > 1 抛 [DkVersionTooHighException]；< 1 触发占位升级器。
@immutable
class DkScore {
  const DkScore({
    required this.dkVersion,
    required this.meta,
    required this.tracks,
    required this.tempoMap,
  });

  final String dkVersion;
  final DkMeta meta;
  final List<DkTrack> tracks;
  final List<DkTempoEvent> tempoMap;

  static const int _supportedMajor = 1;

  factory DkScore.fromJson(
    Map<String, dynamic> json, {
    void Function(String)? onWarning,
  }) {
    final String version = json['dkVersion'] as String;
    final _SemVer parsed = _SemVer.parse(version);
    if (parsed.major > _supportedMajor) {
      throw DkVersionTooHighException(
        'DK 谱版本 $version 高于当前支持的 $_supportedMajor.x，请升级 App。',
      );
    }
    if (parsed.major < _supportedMajor) {
      onWarning?.call(
        'DK 谱版本 $version 低于当前版本，已按占位升级器处理为 $_supportedMajor.0。',
      );
    }
    final List<DkTrack> tracks = (json['tracks'] as List<dynamic>)
        .map((dynamic e) =>
            DkTrack.fromJson(e as Map<String, dynamic>, onWarning: onWarning))
        .toList();
    final List<DkTempoEvent> tempoMap = (json['tempoMap'] as List<dynamic>)
        .map((dynamic e) => DkTempoEvent.fromJson(e as Map<String, dynamic>))
        .toList();
    return DkScore(
      dkVersion: version,
      meta: DkMeta.fromJson(json['meta'] as Map<String, dynamic>),
      tracks: tracks,
      tempoMap: tempoMap,
    );
  }

  factory DkScore.fromJsonString(
    String s, {
    void Function(String)? onWarning,
  }) {
    final Map<String, dynamic> json = jsonDecode(s) as Map<String, dynamic>;
    return DkScore.fromJson(json, onWarning: onWarning);
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'dkVersion': dkVersion,
        'meta': meta.toJson(),
        'tracks': tracks.map((DkTrack t) => t.toJson()).toList(),
        'tempoMap': tempoMap.map((DkTempoEvent e) => e.toJson()).toList(),
      };

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());

  @override
  bool operator ==(Object other) =>
      other is DkScore &&
      other.dkVersion == dkVersion &&
      other.meta == meta &&
      _listEquals(other.tracks, tracks) &&
      _listEquals(other.tempoMap, tempoMap);

  @override
  int get hashCode => Object.hash(
        dkVersion,
        meta,
        Object.hashAll(tracks),
        Object.hashAll(tempoMap),
      );
}

/// 谱面元信息（Version 设计文档 3.1）。
@immutable
class DkMeta {
  const DkMeta({
    required this.title,
    required this.composer,
    required this.sourceMidiSha256,
    required this.bpmBase,
    required this.timeSignature,
    required this.keySignature,
    required this.totalDurationMs,
  });

  final String title;
  final String composer;

  /// 源 MIDI 文件 sha256，用于追溯。
  final String sourceMidiSha256;

  /// 谱面基础 BPM。
  final int bpmBase;

  /// 拍号，如 "4/4"。
  final String timeSignature;

  /// 调号，如 "C"。
  final String keySignature;

  final int totalDurationMs;

  factory DkMeta.fromJson(Map<String, dynamic> json) => DkMeta(
        title: json['title'] as String,
        composer: json['composer'] as String,
        sourceMidiSha256: json['sourceMidiSha256'] as String,
        bpmBase: (json['bpmBase'] as num).toInt(),
        timeSignature: json['timeSignature'] as String,
        keySignature: json['keySignature'] as String,
        totalDurationMs: (json['totalDurationMs'] as num).toInt(),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'title': title,
        'composer': composer,
        'sourceMidiSha256': sourceMidiSha256,
        'bpmBase': bpmBase,
        'timeSignature': timeSignature,
        'keySignature': keySignature,
        'totalDurationMs': totalDurationMs,
      };

  @override
  bool operator ==(Object other) =>
      other is DkMeta &&
      other.title == title &&
      other.composer == composer &&
      other.sourceMidiSha256 == sourceMidiSha256 &&
      other.bpmBase == bpmBase &&
      other.timeSignature == timeSignature &&
      other.keySignature == keySignature &&
      other.totalDurationMs == totalDurationMs;

  @override
  int get hashCode => Object.hash(title, composer, sourceMidiSha256, bpmBase,
      timeSignature, keySignature, totalDurationMs);
}

/// 一条音轨（v1.0.0 固定单轨 id="main"）。
@immutable
class DkTrack {
  const DkTrack({required this.id, required this.notes});

  final String id;

  /// 按 t 升序。
  final List<DkNote> notes;

  factory DkTrack.fromJson(
    Map<String, dynamic> json, {
    void Function(String)? onWarning,
  }) {
    final List<DkNote> parsed = (json['notes'] as List<dynamic>)
        .map((dynamic e) => DkNote.fromJson(e as Map<String, dynamic>))
        .toList();
    if (!_isSortedByT(parsed)) {
      parsed.sort((DkNote a, DkNote b) => a.t.compareTo(b.t));
      onWarning?.call(
        'DkTrack "${json['id']}" 的 notes 原始顺序非升序，已按 t 重新排序。',
      );
    }
    return DkTrack(id: json['id'] as String, notes: parsed);
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'notes': notes.map((DkNote n) => n.toJson()).toList(),
      };

  static bool _isSortedByT(List<DkNote> notes) {
    for (var i = 1; i < notes.length; i++) {
      if (notes[i].t < notes[i - 1].t) {
        return false;
      }
    }
    return true;
  }

  @override
  bool operator ==(Object other) =>
      other is DkTrack && other.id == id && _listEquals(other.notes, notes);

  @override
  int get hashCode => Object.hash(id, Object.hashAll(notes));
}

/// 一个待按下落 key（Version 设计文档 3.1）。
@immutable
class DkNote {
  const DkNote({
    required this.t,
    required this.d,
    required this.pitch,
    required this.velocity,
    this.hand,
    this.finger,
  });

  /// 起始毫秒（相对曲首）。
  final int t;

  /// 持续毫秒。
  final int d;

  /// MIDI 音高 0-127。
  final int pitch;

  /// 0-127。
  final int velocity;

  /// v1.0.0 为 null。
  final String? hand;

  /// v1.0.0 为 null。
  final int? finger;

  factory DkNote.fromJson(Map<String, dynamic> json) => DkNote(
        t: (json['t'] as num).toInt(),
        d: (json['d'] as num).toInt(),
        pitch: (json['pitch'] as num).toInt(),
        velocity: (json['velocity'] as num).toInt(),
        hand: json['hand'] as String?,
        finger: (json['finger'] as num?)?.toInt(),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        't': t,
        'd': d,
        'pitch': pitch,
        'velocity': velocity,
        'hand': hand,
        'finger': finger,
      };

  @override
  bool operator ==(Object other) =>
      other is DkNote &&
      other.t == t &&
      other.d == d &&
      other.pitch == pitch &&
      other.velocity == velocity &&
      other.hand == hand &&
      other.finger == finger;

  @override
  int get hashCode => Object.hash(t, d, pitch, velocity, hand, finger);
}

/// 变速事件（Version 设计文档 3.1）。
@immutable
class DkTempoEvent {
  const DkTempoEvent({required this.t, required this.bpm});

  /// 毫秒。
  final int t;

  /// 该时刻起的瞬时 BPM。
  final double bpm;

  factory DkTempoEvent.fromJson(Map<String, dynamic> json) => DkTempoEvent(
        t: (json['t'] as num).toInt(),
        bpm: (json['bpm'] as num).toDouble(),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{'t': t, 'bpm': bpm};

  @override
  bool operator ==(Object other) =>
      other is DkTempoEvent && other.t == t && other.bpm == bpm;

  @override
  int get hashCode => Object.hash(t, bpm);
}

/// 语义化版本号解析（仅取 major.minor）。
@immutable
class _SemVer {
  const _SemVer(this.major, this.minor);

  final int major;
  final int minor;

  static _SemVer parse(String s) {
    final List<String> parts = s.split('.');
    final int major =
        parts.isNotEmpty ? int.tryParse(parts[0]) ?? 0 : 0;
    final int minor = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    return _SemVer(major, minor);
  }
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) {
    return true;
  }
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}
