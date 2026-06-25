import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/app_config.dart';
import '../domain/models/dk_score.dart';
import '../domain/models/midi_data.dart';
import '../domain/exceptions/dk_exception.dart';
import '../domain/ports/config_repository_port.dart';
import '../domain/ports/file_system_port.dart';
import '../domain/ports/midi_input_port.dart';
import '../domain/services/dk_generator.dart';
import '../domain/services/midi_parser.dart';
import '../platform/android/android_config_repository.dart';
import '../platform/debug/debug_midi_injector.dart';
import '../platform/debug/in_memory_fs_port.dart';

// ==================== Infrastructure ====================

final configRepositoryProvider = Provider<ConfigRepositoryPort>((_) {
  return AndroidConfigRepository();
});

final fileSystemProvider = Provider<FileSystemPort>((_) {
  return InMemoryFileSystemPort.withSampleData();
});

final midiInputProvider = Provider<MidiInputPort>((_) {
  return DebugMidiInjector();
});

final midiParserProvider = Provider<MidiParser>((_) => MidiParser());
final dkGeneratorProvider = Provider<DkGenerator>((_) => DkGenerator());

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
    this.selectedTrackIndex,
    this.title = '',
    this.composer = '',
  });

  final ConvertPageState page;
  final String message;
  final MidiData? midiData;
  final int? selectedTrackIndex;
  final String title;
  final String composer;

  factory ConvertState.initial() =>
      const ConvertState._(page: ConvertPageState.aNoFile);

  ConvertState copyWith({
    ConvertPageState? page,
    String? message,
    MidiData? midiData,
    Object? selectedTrackIndex = _sentinel,
    String? title,
    String? composer,
  }) {
    return ConvertState._(
      page: page ?? this.page,
      message: message ?? this.message,
      midiData: midiData ?? this.midiData,
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
    _parser = ref.read(midiParserProvider);
    _generator = ref.read(dkGeneratorProvider);
    return ConvertState.initial();
  }

  late final FileSystemPort _fs;
  late final MidiParser _parser;
  late final DkGenerator _generator;

  void reset() {
    state = ConvertState.initial();
  }

  Future<void> pickFile() async {
    try {
      final String? path = await _fs.pickMidiFile();
      if (path == null) return;
    } on Exception catch (e) {
      state = state.copyWith(
          page: ConvertPageState.eError, message: e.toString());
    }
  }

  void injectRawBytes(Uint8List bytes) {
    try {
      final MidiData data = _parser.parse(bytes);
      state = state.copyWith(
        page: ConvertPageState.bSelectTrack,
        midiData: data,
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

  void setTitle(String v) {
    state = state.copyWith(title: v);
  }

  void setComposer(String v) {
    state = state.copyWith(composer: v);
  }

  void toSave() {
    state = state.copyWith(page: ConvertPageState.dSave);
  }

  Future<void> confirmSave() async {
    final MidiData? data = state.midiData;
    if (data == null) return;
    final DkScore score = _generator.generate(
      data,
      melodyTrackIndex: state.selectedTrackIndex,
      title: state.title,
      composer: state.composer,
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
