// ignore_for_file: avoid_print
//
// 生成 Stage 3 解析测试所需的合法/异常 SMF fixture（写入 test/fixtures/）。
// 用法（app/ 目录）：dart run tool/gen_midi_fixtures.dart
import 'dart:io';

const int _division = 480; // ticks per quarter
const int _q = 480; // 一个四分音符的 tick 数

List<int> _vlq(int value) {
  if (value == 0) {
    return <int>[0];
  }
  final List<int> stack = <int>[];
  var v = value;
  stack.add(v & 0x7F);
  v >>= 7;
  while (v > 0) {
    stack.add((v & 0x7F) | 0x80);
    v >>= 7;
  }
  return stack.reversed.toList();
}

List<int> _u16(int v) => <int>[(v >> 8) & 0xFF, v & 0xFF];
List<int> _u32(int v) =>
    <int>[(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF];

/// 一个带 delta 的事件。
class _Ev {
  _Ev(this.delta, this.bytes);
  final int delta;
  final List<int> bytes;
}

List<int> _noteOn(int ch, int pitch, int vel) =>
    <int>[0x90 | ch, pitch, vel];
List<int> _noteOff(int ch, int pitch) => <int>[0x80 | ch, pitch, 0x40];
List<int> _tempo(int usPerQuarter) => <int>[
      0xFF, 0x51, 0x03,
      (usPerQuarter >> 16) & 0xFF,
      (usPerQuarter >> 8) & 0xFF,
      usPerQuarter & 0xFF,
    ];
List<int> _timeSig(int nn, int dd) =>
    <int>[0xFF, 0x58, 0x04, nn, dd, 24, 8];
List<int> _keySig(int sf, int mi) =>
    <int>[0xFF, 0x59, 0x02, sf & 0xFF, mi];
List<int> _trackName(String name) {
  final List<int> chars = name.codeUnits;
  return <int>[0xFF, 0x03, chars.length, ...chars];
}

final List<int> _endOfTrack = <int>[0xFF, 0x2F, 0x00];

List<int> _buildTrack(List<_Ev> events) {
  final List<int> body = <int>[];
  for (final _Ev e in events) {
    body.addAll(_vlq(e.delta));
    body.addAll(e.bytes);
  }
  return <int>['M'.codeUnitAt(0), 'T'.codeUnitAt(0), 'r'.codeUnitAt(0),
    'k'.codeUnitAt(0), ..._u32(body.length), ...body];
}

List<int> _header(int format, int ntrks) => <int>[
      'M'.codeUnitAt(0), 'T'.codeUnitAt(0), 'h'.codeUnitAt(0),
      'd'.codeUnitAt(0),
      ..._u32(6),
      ..._u16(format),
      ..._u16(ntrks),
      ..._u16(_division),
    ];

/// 顺序排列的 note：每个 [pitch] 占一个四分音符。
List<_Ev> _scale(List<int> pitches, {int ch = 0}) {
  final List<_Ev> ev = <_Ev>[];
  for (final int p in pitches) {
    ev.add(_Ev(0, _noteOn(ch, p, 0x64)));
    ev.add(_Ev(_q, _noteOff(ch, p)));
  }
  return ev;
}

void main() {
  final Directory dir = Directory('test/fixtures');
  dir.createSync(recursive: true);
  final List<String> written = <String>[];

  void write(String name, List<int> bytes) {
    final String path = '${dir.path}/$name';
    File(path).writeAsBytesSync(bytes);
    written.add(path);
  }

  // 1. f0_cmajor_scale.mid（格式0，C 大调音阶 8 音，120bpm，4/4）
  {
    final List<_Ev> ev = <_Ev>[
      _Ev(0, _tempo(500000)),
      _Ev(0, _timeSig(4, 2)),
      ..._scale(<int>[60, 62, 64, 65, 67, 69, 71, 72]),
      _Ev(0, _endOfTrack),
    ];
    write('f0_cmajor_scale.mid', <int>[..._header(0, 1), ..._buildTrack(ev)]);
  }

  // 2. f1_two_tracks.mid（格式1，旋律 + 低音，含 Track Name）
  {
    final List<_Ev> melody = <_Ev>[
      _Ev(0, _trackName('Melody')),
      _Ev(0, _tempo(500000)),
      _Ev(0, _timeSig(4, 2)),
      ..._scale(<int>[60, 62, 64, 65]),
      _Ev(0, _endOfTrack),
    ];
    final List<_Ev> bass = <_Ev>[
      _Ev(0, _trackName('Bass')),
      ..._scale(<int>[48, 50, 52, 53], ch: 1),
      _Ev(0, _endOfTrack),
    ];
    write('f1_two_tracks.mid',
        <int>[..._header(1, 2), ..._buildTrack(melody), ..._buildTrack(bass)]);
  }

  // 3. f1_tempo_change.mid（格式1，曲中 120→90）
  {
    final List<_Ev> ev = <_Ev>[
      _Ev(0, _tempo(500000)), // 120bpm
      ..._scale(<int>[60, 62, 64, 65]),
      _Ev(0, _tempo(666667)), // 约 90bpm
      ..._scale(<int>[67, 69, 71, 72]),
      _Ev(0, _endOfTrack),
    ];
    write('f1_tempo_change.mid', <int>[..._header(1, 1), ..._buildTrack(ev)]);
  }

  // 4. f1_timesig_keysig.mid（格式1，3/4、G 大调）
  {
    final List<_Ev> ev = <_Ev>[
      _Ev(0, _tempo(500000)),
      _Ev(0, _timeSig(3, 2)),
      _Ev(0, _keySig(1, 0)),
      ..._scale(<int>[67, 71]),
      _Ev(0, _endOfTrack),
    ];
    write('f1_timesig_keysig.mid', <int>[..._header(1, 1), ..._buildTrack(ev)]);
  }

  // 5. format2.mid（格式2，应触发 UnsupportedMidiFormatException）
  {
    final List<_Ev> ev = <_Ev>[
      _Ev(0, _noteOn(0, 60, 0x64)),
      _Ev(_q, _noteOff(0, 60)),
      _Ev(0, _endOfTrack),
    ];
    write('format2.mid', <int>[..._header(2, 1), ..._buildTrack(ev)]);
  }

  // 6. corrupted.mid（MThd 头损坏，应触发 CorruptedMidiException）
  {
    write('corrupted.mid', <int>[
      'M'.codeUnitAt(0), 'T'.codeUnitAt(0), 'h'.codeUnitAt(0),
      'X'.codeUnitAt(0), // 'd' 被破坏
      ..._u32(6),
      ..._u16(1),
      ..._u16(1),
      ..._u16(_division),
    ]);
  }

  print('Generated ${written.length} MIDI fixtures:');
  for (final String p in written) {
    print('  $p');
  }
}
