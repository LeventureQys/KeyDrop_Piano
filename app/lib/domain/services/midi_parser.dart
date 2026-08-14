import 'dart:typed_data';

import '../exceptions/dk_exception.dart';
import '../models/midi_data.dart';

/// Standard MIDI File（SMF）解析器（Version C2 / Stage 3 设计文档 4）。
///
/// 仅接收字节数组，**不接触文件路径 / dart:io**（领域层零平台依赖）。
/// 支持格式 0/1、metrical division；格式 2 / SMPTE / 损坏 / 无音符均抛
/// [DkException] 子类。
class MidiParser {
  /// 解析 SMF 字节为 [MidiData]。
  MidiData parse(Uint8List bytes) {
    final _Reader r = _Reader(bytes);

    // ---- Header chunk ----
    final String magic = r.readAscii(4);
    if (magic != 'MThd') {
      throw CorruptedMidiException('文件已损坏：在 chunk header 处读取失败。');
    }
    final int headerLen = r.readU32();
    if (headerLen != 6) {
      throw CorruptedMidiException('文件已损坏：MThd 长度字段异常 ($headerLen)。');
    }
    final int format = r.readU16();
    final int ntrks = r.readU16();
    final int division = r.readU16();

    if (format == 2) {
      throw UnsupportedMidiFormatException(
        '此文件为 SMF 格式 2，v1.0.0 仅支持格式 0/1。',
      );
    }
    if (format != 0 && format != 1) {
      throw UnsupportedMidiFormatException('未知的 SMF 格式 ($format)。');
    }
    if ((division & 0x8000) != 0) {
      throw UnsupportedMidiFormatException('此文件使用 SMPTE 时基，暂不支持。');
    }
    final int ticksPerQuarter = division & 0x7FFF;
    if (ticksPerQuarter <= 0) {
      throw CorruptedMidiException('文件已损坏：division 字段异常。');
    }

    // ---- Track chunks ----
    final List<_RawNote> rawNotes = <_RawNote>[];
    final List<_TempoEvt> tempoEvts = <_TempoEvt>[];
    _MetaStr? timeSig;
    _MetaStr? keySig;
    final Map<int, String> trackNames = <int, String>{};

    for (var trackIndex = 0; trackIndex < ntrks; trackIndex++) {
      if (r.remaining < 8) {
        // 部分文件 ntrks 多报；容忍提前结束。
        break;
      }
      final String tMagic = r.readAscii(4);
      if (tMagic != 'MTrk') {
        throw CorruptedMidiException('文件已损坏：音轨数据读取失败。');
      }
      final int trackLen = r.readU32();
      final int trackEnd = r.pos + trackLen;
      if (trackEnd > bytes.length) {
        throw CorruptedMidiException('文件已损坏：音轨数据读取失败。');
      }

      var absTick = 0;
      var runningStatus = -1;
      final Map<int, List<_OpenNote>> open = <int, List<_OpenNote>>{};

      while (r.pos < trackEnd) {
        absTick += r.readVlq();
        var status = r.peekU8();
        if (status < 0x80) {
          if (runningStatus < 0) {
            throw CorruptedMidiException('文件已损坏：running status 缺失。');
          }
          status = runningStatus;
        } else {
          r.skip(1);
          if (status < 0xF0) {
            runningStatus = status;
          } else {
            runningStatus = -1; // system message cancels running status
          }
        }

        final int hi = status & 0xF0;
        final int channel = status & 0x0F;

        if (hi == 0x90) {
          // Note On
          final int pitch = r.readU8();
          final int velocity = r.readU8();
          if (velocity == 0) {
            _closeNote(open, channel, pitch, absTick, rawNotes, trackIndex);
          } else {
            open
                .putIfAbsent(_key(channel, pitch), () => <_OpenNote>[])
                .add(_OpenNote(absTick, velocity));
          }
        } else if (hi == 0x80) {
          // Note Off
          final int pitch = r.readU8();
          r.readU8(); // velocity，忽略
          _closeNote(open, channel, pitch, absTick, rawNotes, trackIndex);
        } else if (hi == 0xA0 || hi == 0xB0 || hi == 0xE0) {
          r.skip(2); // poly aftertouch / control change / pitch bend
        } else if (hi == 0xC0 || hi == 0xD0) {
          r.skip(1); // program change / channel pressure
        } else if (status == 0xF0 || status == 0xF7) {
          final int len = r.readVlq();
          r.skip(len); // SysEx，忽略
        } else if (status == 0xFF) {
          final int metaType = r.readU8();
          final int len = r.readVlq();
          final int dataStart = r.pos;
          if (metaType == 0x51 && len == 3) {
            final int us = (bytes[dataStart] << 16) |
                (bytes[dataStart + 1] << 8) |
                bytes[dataStart + 2];
            if (us > 0) {
              tempoEvts.add(_TempoEvt(absTick, us));
            }
          } else if (metaType == 0x58 && len >= 2) {
            final int nn = bytes[dataStart];
            final int dd = bytes[dataStart + 1];
            timeSig ??= _MetaStr('$nn/${1 << dd}');
          } else if (metaType == 0x59 && len == 2) {
            final int sf = bytes[dataStart].toSigned(8);
            final int mi = bytes[dataStart + 1];
            keySig ??= _MetaStr(_keySigName(sf, mi));
          } else if (metaType == 0x03 && len > 0) {
            trackNames[trackIndex] =
                String.fromCharCodes(bytes.sublist(dataStart, dataStart + len));
          }
          r.skip(len);
          if (metaType == 0x2F) {
            break; // End of Track
          }
        } else {
          throw CorruptedMidiException('文件已损坏：未知事件状态 0x${status.toRadixString(16)}。');
        }
      }

      // 关闭轨尾仍未闭合的 note
      for (final List<_OpenNote> notes in open.values) {
        for (final _OpenNote n in notes) {
          rawNotes.add(_RawNote(
            trackIndex: trackIndex,
            channel: -1,
            startTick: n.startTick,
            endTick: absTick,
            pitch: -1,
            velocity: n.velocity,
          ));
        }
      }
      r.pos = trackEnd; // 对齐到下一 chunk
    }

    // ---- 构建全局 tempo 段 ----
    tempoEvts.sort((_TempoEvt a, _TempoEvt b) => a.tick.compareTo(b.tick));
    final List<_TempoSeg> segs = <_TempoSeg>[];
    if (tempoEvts.isEmpty || tempoEvts.first.tick > 0) {
      segs.add(const _TempoSeg(0, 500000)); // 默认 120bpm
    }
    for (final _TempoEvt e in tempoEvts) {
      if (segs.isNotEmpty && segs.last.tick == e.tick) {
        segs[segs.length - 1] = _TempoSeg(e.tick, e.us);
      } else {
        segs.add(_TempoSeg(e.tick, e.us));
      }
    }

    // ---- note tick→ms + 统计 ----
    final List<MidiNoteEvent> notes = <MidiNoteEvent>[];
    for (final _RawNote rn in rawNotes) {
      if (rn.pitch < 0) {
        continue; // 关闭失败的孤立 note（pitch 未知，丢弃）
      }
      final int startMs = _tickToMs(rn.startTick, segs, ticksPerQuarter);
      final int endMs = _tickToMs(rn.endTick, segs, ticksPerQuarter);
      notes.add(MidiNoteEvent(
        trackIndex: rn.trackIndex,
        channel: rn.channel,
        startMs: startMs,
        durationMs: (endMs - startMs).clamp(1, 1 << 30),
        pitch: rn.pitch,
        velocity: rn.velocity,
      ));
    }
    notes.sort((MidiNoteEvent a, MidiNoteEvent b) {
      final int byStart = a.startMs.compareTo(b.startMs);
      return byStart != 0 ? byStart : a.pitch.compareTo(b.pitch);
    });

    if (notes.isEmpty) {
      throw UnsupportedMidiFormatException('未在文件中找到可演奏的音符。');
    }

    var totalDurationMs = 0;
    for (final MidiNoteEvent n in notes) {
      final int end = n.startMs + n.durationMs;
      if (end > totalDurationMs) {
        totalDurationMs = end;
      }
    }

    // ---- tempoMap (ms) ----
    final List<MidiTempoChange> tempoMap = <MidiTempoChange>[];
    for (final _TempoSeg s in segs) {
      tempoMap.add(MidiTempoChange(
        _tickToMs(s.tick, segs, ticksPerQuarter),
        60000000.0 / s.us,
      ));
    }

    // ---- 轨道统计 ----
    final List<MidiTrackInfo> tracks = <MidiTrackInfo>[];
    final int trackCount = format == 0 ? 1 : ntrks;
    for (var ti = 0; ti < trackCount; ti++) {
      final List<MidiNoteEvent> tn =
          notes.where((MidiNoteEvent n) => n.trackIndex == ti).toList();
      var minP = -1;
      var maxP = -1;
      var ch = -1;
      for (final MidiNoteEvent n in tn) {
        if (minP < 0 || n.pitch < minP) {
          minP = n.pitch;
        }
        if (maxP < 0 || n.pitch > maxP) {
          maxP = n.pitch;
        }
        if (ch < 0) {
          ch = n.channel;
        }
      }
      tracks.add(MidiTrackInfo(
        trackIndex: ti,
        channel: ch,
        noteCount: tn.length,
        minPitch: minP,
        maxPitch: maxP,
        trackName: trackNames[ti],
      ));
    }

    return MidiData(
      format: format == 0 ? MidiFormat.single : MidiFormat.multiTrack,
      ticksPerQuarter: ticksPerQuarter,
      notes: notes,
      tempoMap: tempoMap,
      timeSignature: timeSig?.value ?? '4/4',
      keySignature: keySig?.value ?? 'C',
      totalDurationMs: totalDurationMs,
      tracks: tracks,
    );
  }

  static int _key(int channel, int pitch) => (channel << 8) | pitch;

  static void _closeNote(
    Map<int, List<_OpenNote>> open,
    int channel,
    int pitch,
    int endTick,
    List<_RawNote> out,
    int trackIndex,
  ) {
    final List<_OpenNote>? stack = open[_key(channel, pitch)];
    if (stack == null || stack.isEmpty) {
      return;
    }
    final _OpenNote n = stack.removeLast();
    out.add(_RawNote(
      trackIndex: trackIndex,
      channel: channel,
      startTick: n.startTick,
      endTick: endTick,
      pitch: pitch,
      velocity: n.velocity,
    ));
  }

  static int _tickToMs(int tick, List<_TempoSeg> segs, int tpq) {
    var accMs = 0.0;
    var segStart = segs.first.tick;
    var curUs = segs.first.us;
    for (var i = 1; i < segs.length; i++) {
      final int nextTick = segs[i].tick;
      if (tick <= nextTick) {
        break;
      }
      accMs += (nextTick - segStart) * curUs / tpq / 1000.0;
      segStart = nextTick;
      curUs = segs[i].us;
    }
    accMs += (tick - segStart) * curUs / tpq / 1000.0;
    return accMs.round();
  }

  static String _keySigName(int sf, int mi) {
    const List<String> major = <String>[
      'Cb', 'Gb', 'Db', 'Ab', 'Eb', 'Bb', 'F', // sf -7..-1
      'C', // sf 0
      'G', 'D', 'A', 'E', 'B', 'F#', 'C#', // sf 1..7
    ];
    const List<String> minor = <String>[
      'Abm', 'Ebm', 'Bbm', 'Fm', 'Cm', 'Gm', 'Dm', // sf -7..-1
      'Am', // sf 0
      'Em', 'Bm', 'F#m', 'C#m', 'G#m', 'D#m', 'A#m', // sf 1..7
    ];
    if (sf < -7 || sf > 7) {
      return 'C';
    }
    final int idx = sf + 7;
    return mi == 1 ? minor[idx] : major[idx];
  }
}

class _Reader {
  _Reader(this.bytes);

  final Uint8List bytes;
  int pos = 0;

  int get remaining => bytes.length - pos;

  void skip(int n) {
    pos += n;
    if (pos > bytes.length) {
      throw CorruptedMidiException('文件已损坏：读取越界。');
    }
  }

  int peekU8() {
    if (pos >= bytes.length) {
      throw CorruptedMidiException('文件已损坏：读取越界。');
    }
    return bytes[pos];
  }

  int readU8() {
    final int v = peekU8();
    pos++;
    return v;
  }

  int readU16() => (readU8() << 8) | readU8();

  int readU32() =>
      (readU8() << 24) | (readU8() << 16) | (readU8() << 8) | readU8();

  String readAscii(int n) {
    if (pos + n > bytes.length) {
      throw CorruptedMidiException('文件已损坏：读取越界。');
    }
    final String s = String.fromCharCodes(bytes.sublist(pos, pos + n));
    pos += n;
    return s;
  }

  int readVlq() {
    var value = 0;
    var count = 0;
    while (true) {
      final int b = readU8();
      value = (value << 7) | (b & 0x7F);
      count++;
      if ((b & 0x80) == 0) {
        break;
      }
      if (count > 4) {
        throw CorruptedMidiException('文件已损坏：可变长度量过长。');
      }
    }
    return value;
  }
}

class _OpenNote {
  _OpenNote(this.startTick, this.velocity);
  final int startTick;
  final int velocity;
}

class _RawNote {
  _RawNote({
    required this.trackIndex,
    required this.channel,
    required this.startTick,
    required this.endTick,
    required this.pitch,
    required this.velocity,
  });
  final int trackIndex;
  final int channel;
  final int startTick;
  final int endTick;
  final int pitch;
  final int velocity;
}

class _TempoEvt {
  _TempoEvt(this.tick, this.us);
  final int tick;
  final int us;
}

class _TempoSeg {
  const _TempoSeg(this.tick, this.us);
  final int tick;
  final int us;
}

class _MetaStr {
  _MetaStr(this.value);
  final String value;
}
