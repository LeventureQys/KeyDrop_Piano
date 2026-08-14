import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/exceptions/dk_exception.dart';
import '../domain/models/app_config.dart';
import '../domain/models/dk_score.dart';
import '../domain/models/midi_data.dart';
import '../domain/ports/config_repository_port.dart';
import '../domain/ports/file_system_port.dart';
import '../domain/ports/lifecycle_port.dart';
import '../domain/ports/midi_input_port.dart';
import '../domain/services/dk_generator.dart';
import '../domain/services/midi_parser.dart';
import '../platform/android/android_config_repository.dart';
import '../platform/android/android_file_system_adapter.dart';
import '../platform/android/android_lifecycle_adapter.dart';
import '../platform/android/android_midi_input_adapter.dart';
import '../platform/debug/debug_midi_injector.dart';
import '../platform/debug/in_memory_fs_port.dart';

// ==================== Infrastructure ====================
//
// 生产/调试装配规则（Stage 4.3 + Stage 5 设计文档 2）：
// - Android：真实平台实现（SAF 文件系统 / USB MIDI / shared_preferences）。
// - 其他平台（桌面开发 / 测试）：内存文件系统 + 空 MIDI 注入器。
// - debug 构建：MIDI 输入用 DebugMidiInjector 装饰真实适配器，
//   集成测试可注入伪事件，真机调试仍保留真实 USB MIDI 能力。

final configRepositoryProvider = Provider<ConfigRepositoryPort>((_) {
  return AndroidConfigRepository();
});

final lifecycleProvider = Provider<LifecyclePort>((_) {
  if (defaultTargetPlatform == TargetPlatform.android) {
    return AndroidLifecycleAdapter();
  }
  return const _NoopLifecycle();
});

final fileSystemProvider = Provider<FileSystemPort>((_) {
  if (defaultTargetPlatform == TargetPlatform.android) {
    return AndroidFileSystemAdapter();
  }
  // 桌面开发环境：内存实现（Stage 5 设计文档 2）。
  return InMemoryFileSystemPort.withSampleData();
});

final midiInputProvider = Provider<MidiInputPort>((_) {
  if (defaultTargetPlatform == TargetPlatform.android) {
    final MidiInputPort real = AndroidMidiInputAdapter();
    if (kDebugMode) {
      return DebugMidiInjector(real);
    }
    return real;
  }
  // 桌面/测试：注入器（无真实设备）。
  return DebugMidiInjector.none();
});

final midiParserProvider = Provider<MidiParser>((_) => MidiParser());
final dkGeneratorProvider = Provider<DkGenerator>((_) => DkGenerator());

/// 顶层入口：在后台 isolate 中解析 MIDI（Version 禁止事项 F-05：
/// 禁止在主线程做 MIDI 文件解析）。与 `compute` 配合使用。
MidiData parseMidiBytesInIsolate(Uint8List bytes) => MidiParser().parse(bytes);

/// 计算字节的 sha256（DK 谱 meta.sourceMidiSha256 追溯字段）。
String sha256Of(Uint8List bytes) => sha256.convert(bytes).toString();

/// 无平台能力时的空实现（桌面）。
class _NoopLifecycle implements LifecyclePort {
  const _NoopLifecycle();

  @override
  Future<void> setKeepScreenOn(bool enabled) async {}
}

// ==================== AppConfig ====================

class AppConfigNotifier extends Notifier<AppConfig> {
  @override
  AppConfig build() {
    final ConfigRepositoryPort repo = ref.read(configRepositoryProvider);
    Future<void>.microtask(() async {
      state = await repo.load();
    });
    return AppConfig.defaults;
  }

  Future<void> _save(AppConfig next) async {
    final ConfigRepositoryPort repo = ref.read(configRepositoryProvider);
    await repo.save(next);
    state = next;
  }

  void setHardwareKeyboardKeys(int v) =>
      _save(state.copyWith(hardwareKeyboardKeys: v));
  void setViewportKeys(int v) => _save(state.copyWith(viewportKeys: v));
  void setScrollMode(ScrollMode v) => _save(state.copyWith(scrollMode: v));
  void setFallDurationSeconds(double v) =>
      _save(state.copyWith(fallDurationSeconds: v));
  void setJudgmentWidth(JudgmentWidth v) =>
      _save(state.copyWith(judgmentWidth: v));
  void setInputLatencyOffsetMs(int v) =>
      _save(state.copyWith(inputLatencyOffsetMs: v));
  void setBpmMultiplier(double v) => _save(state.copyWith(bpmMultiplier: v));
  void setDefaultMode(PlayMode v) => _save(state.copyWith(defaultMode: v));
  void setEnableDebugMidiInjector(bool v) =>
      _save(state.copyWith(enableDebugMidiInjector: v));
}

final appConfigProvider =
    NotifierProvider<AppConfigNotifier, AppConfig>(AppConfigNotifier.new);

// ==================== Score List ====================

final scoreListProvider =
    FutureProvider.autoDispose<List<DkScoreFile>>((ref) async {
  final FileSystemPort fs = ref.read(fileSystemProvider);
  return fs.listDkScores();
});

// ==================== Convert Flow ====================

enum ConvertPageState { aNoFile, bSelectTrack, cPreview, dSave, eError }

class ConvertState {
  const ConvertState._({
    required this.page,
    this.message = '',
    this.midiData,
    this.midiBytes,
    this.sourceMidiSha256 = '',
    this.selectedTrackIndex,
    this.title = '',
    this.composer = '',
  });

  final ConvertPageState page;
  final String message;
  final MidiData? midiData;
  final Uint8List? midiBytes;
  final String sourceMidiSha256;
  final int? selectedTrackIndex;
  final String title;
  final String composer;

  factory ConvertState.initial() =>
      const ConvertState._(page: ConvertPageState.aNoFile);

  ConvertState copyWith({
    ConvertPageState? page,
    String? message,
    MidiData? midiData,
    Uint8List? midiBytes,
    String? sourceMidiSha256,
    Object? selectedTrackIndex = _sentinel,
    String? title,
    String? composer,
  }) {
    return ConvertState._(
      page: page ?? this.page,
      message: message ?? this.message,
      midiData: midiData ?? this.midiData,
      midiBytes: midiBytes ?? this.midiBytes,
      sourceMidiSha256: sourceMidiSha256 ?? this.sourceMidiSha256,
      selectedTrackIndex: selectedTrackIndex is int
          ? selectedTrackIndex
          : this.selectedTrackIndex,
      title: title ?? this.title,
      composer: composer ?? this.composer,
    );
  }

  static const Object _sentinel = Object();
}

class ConvertStateNotifier extends Notifier<ConvertState> {
  @override
  ConvertState build() {
    _fs = ref.read(fileSystemProvider);
    _generator = ref.read(dkGeneratorProvider);
    return ConvertState.initial();
  }

  late final FileSystemPort _fs;
  late final DkGenerator _generator;

  void reset() {
    state = ConvertState.initial();
  }

  /// SAF 选择 MIDI → 平台层读字节 → isolate 解析 → 选轨。
  Future<void> pickFile() async {
    try {
      final String? path = await _fs.pickMidiFile();
      if (path == null) {
        return; // 用户取消
      }
      await _loadPicked(path);
    } on DkException catch (e) {
      state = state.copyWith(
        page: ConvertPageState.eError,
        message: e.message,
      );
    }
  }

  Future<void> _loadPicked(String path) async {
    final Uint8List? bytes = await _fs.readMidiFile(path);
    if (bytes == null || bytes.isEmpty) {
      state = state.copyWith(
        page: ConvertPageState.eError,
        message: '读取所选 MIDI 文件失败，请重试。',
      );
      return;
    }
    // F-05：解析必须在后台 isolate 中进行，不阻塞 UI。
    final MidiData data = await compute(parseMidiBytesInIsolate, bytes);
    final String hash = sha256Of(bytes);
    state = state.copyWith(
      page: ConvertPageState.bSelectTrack,
      midiData: data,
      midiBytes: bytes,
      sourceMidiSha256: hash,
      selectedTrackIndex: null,
      title: data.tracks.isNotEmpty && data.tracks.first.trackName != null
          ? data.tracks.first.trackName!
          : '',
    );
  }

  /// 直接注入 MIDI 字节（测试 / 无 SAF 平台使用）。
  Future<void> injectRawBytes(Uint8List bytes) async {
    try {
      final MidiData data = await compute(parseMidiBytesInIsolate, bytes);
      final String hash = sha256Of(bytes);
      state = state.copyWith(
        page: ConvertPageState.bSelectTrack,
        midiData: data,
        midiBytes: bytes,
        sourceMidiSha256: hash,
        selectedTrackIndex: null,
      );
    } on DkException catch (e) {
      state = state.copyWith(
        page: ConvertPageState.eError,
        message: e.message,
      );
    }
  }

  void selectTrack(int trackIndex) {
    state = state.copyWith(
      page: ConvertPageState.cPreview,
      selectedTrackIndex: trackIndex,
    );
  }

  /// 回到选轨（预览页"上一步"）。
  void backToTrack() {
    state = state.copyWith(page: ConvertPageState.bSelectTrack);
  }

  void setTitle(String v) {
    state = state.copyWith(title: v);
  }

  void setComposer(String v) {
    state = state.copyWith(composer: v);
  }

  void toSave() {
    state = state.copyWith(page: ConvertPageState.dSave);
  }

  /// 生成 DK 谱 JSON 并写入谱面库（含 sha256 追溯）。
  Future<void> confirmSave() async {
    final MidiData? data = state.midiData;
    if (data == null) {
      return;
    }
    // 选轨语义：null = 未选择；< 0（哨兵 -1）= 合并全部轨道。
    final int? sel = state.selectedTrackIndex;
    final int? melodyTrackIndex = (sel == null || sel < 0) ? null : sel;
    final DkScore score = _generator.generate(
      data,
      melodyTrackIndex: melodyTrackIndex,
      title: state.title,
      composer: state.composer,
      sourceMidiSha256: state.sourceMidiSha256,
    );
    final String json = score.toJsonString();
    final String fileName =
        state.title.isNotEmpty ? state.title : 'untitled';
    await _fs.writeDkScore(fileName, json);
    reset();
  }

  void dismissError() {
    reset();
  }
}

final convertStateProvider =
    NotifierProvider<ConvertStateNotifier, ConvertState>(
        ConvertStateNotifier.new);
