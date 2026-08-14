import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:keydrop_piano/di/providers.dart';
import 'package:keydrop_piano/domain/exceptions/dk_exception.dart';
import 'package:keydrop_piano/domain/models/app_config.dart';
import 'package:keydrop_piano/domain/models/dk_score.dart';
import 'package:keydrop_piano/domain/models/midi_data.dart';
import 'package:keydrop_piano/domain/ports/lifecycle_port.dart';
import 'package:keydrop_piano/domain/ports/midi_input_port.dart';
import 'package:keydrop_piano/domain/services/dk_generator.dart';
import 'package:keydrop_piano/domain/services/midi_parser.dart';
import 'package:keydrop_piano/domain/services/statistics_aggregator.dart';
import 'package:keydrop_piano/platform/debug/debug_midi_injector.dart';
import 'package:keydrop_piano/platform/debug/in_memory_fs_port.dart';
import 'package:keydrop_piano/ui/pages/convert_page.dart';
import 'package:keydrop_piano/ui/pages/player_controller.dart';
import 'package:keydrop_piano/ui/pages/player_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Version 验收文档 V3：端到端集成测试（DebugMidiInjector 注入伪 MIDI）。
///
/// 运行方式（需已连接 Android 设备或模拟器，debug 构建含 DebugMidiInjector）：
///   flutter test integration_test/
class _NoopLifecycle implements LifecyclePort {
  const _NoopLifecycle();

  @override
  Future<void> setKeepScreenOn(bool enabled) async {}
}

MidiEvent _noteOn(int pitch, {int velocity = 100}) => MidiEvent(
      type: MidiEventType.noteOn,
      channel: 0,
      pitch: pitch,
      velocity: velocity,
      controllerNumber: 0,
      controllerValue: 0,
      timestampUs: 0,
    );

DkScore _loadScore(String fixtureName) {
  final Uint8List bytes = File('test_fixtures/$fixtureName').readAsBytesSync();
  final MidiData data = MidiParser().parse(bytes);
  return DkGenerator().generate(data);
}

AppConfig _config({
  JudgmentWidth width = JudgmentWidth.wide,
  double bpm = 1.0,
  PlayMode mode = PlayMode.performance,
}) =>
    AppConfig.defaults.copyWith(
      judgmentWidth: width,
      bpmMultiplier: bpm,
      defaultMode: mode,
      inputLatencyOffsetMs: 0,
      fallDurationSeconds: 1.5,
    );

Future<PlayerPageState> _pumpPlayer(
  WidgetTester tester, {
  required DkScore score,
  required AppConfig config,
  required PlayMode mode,
  required DebugMidiInjector injector,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: PlayerPage(
        score: score,
        config: config,
        midiInput: injector,
        lifecycle: const _NoopLifecycle(),
        initialMode: mode,
      ),
    ),
  );
  await tester.pump();
  return tester.state<PlayerPageState>(find.byType(PlayerPage));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('V3-A：导入 simple_format0_8bars.mid 生成的 DK 谱与 golden 一致',
      (WidgetTester tester) async {
    final DkScore generated = _loadScore('simple_format0_8bars.mid');
    final String golden =
        File('test_fixtures/golden_simple_format0_8bars.dk.json')
            .readAsStringSync();
    final String a = golden.replaceAll(RegExp(r'\s+'), '');
    final String b = generated.toJsonString().replaceAll(RegExp(r'\s+'), '');
    expect(b, a);
  });

  testWidgets(
      'V3-B：演奏模式 ±15ms 内注入全部 note → 完美 = 总数，掉 key = 0，错音 = 0',
      (WidgetTester tester) async {
    final DkScore score = _loadScore('simple_format0_8bars.mid');
    final List<DkNote> notes = score.tracks.single.notes;
    final DebugMidiInjector injector = DebugMidiInjector.none();
    final PlayerPageState state = await _pumpPlayer(
      tester,
      score: score,
      config: _config(mode: PlayMode.performance),
      mode: PlayMode.performance,
      injector: injector,
    );

    // note 0 在 t=0。
    injector.inject(_noteOn(notes[0].pitch));
    await tester.pump();
    for (var i = 1; i < notes.length; i++) {
      await tester.pump(const Duration(milliseconds: 500));
      injector.inject(_noteOn(notes[i].pitch));
      await tester.pump();
    }
    // 推进到结束（totalDuration + 2s）。
    await tester.pump(const Duration(milliseconds: 3000));

    expect(state.controller.phase, PlayerPhase.finished);
    final JudgmentStats s = state.controller.stats;
    expect(s.perfect, notes.length);
    expect(s.miss, 0);
    expect(s.error, 0);
  });

  testWidgets(
      'V3-C：学习模式第 3 个 note 按错 1 次再按对 → 错音 = 1，仍能继续到第 4 个 note',
      (WidgetTester tester) async {
    final DkScore score = _loadScore('simple_format0_8bars.mid');
    final List<DkNote> notes = score.tracks.single.notes;
    final DebugMidiInjector injector = DebugMidiInjector.none();
    final PlayerPageState state = await _pumpPlayer(
      tester,
      score: score,
      config: _config(mode: PlayMode.learning),
      mode: PlayMode.learning,
      injector: injector,
    );

    // note 0（t=0）。
    injector.inject(_noteOn(notes[0].pitch));
    await tester.pump();
    // note 1（t=500）。
    await tester.pump(const Duration(milliseconds: 500));
    injector.inject(_noteOn(notes[1].pitch));
    await tester.pump();
    // note 2（t=1000）：先按错音（pitch+1 不在谱面），再按对。
    await tester.pump(const Duration(milliseconds: 500));
    injector.inject(_noteOn(notes[2].pitch + 1));
    await tester.pump();
    expect(state.controller.stats.error, 1);
    expect(state.controller.phase, PlayerPhase.playing); // 仍然卡住等待
    injector.inject(_noteOn(notes[2].pitch));
    await tester.pump();
    // 继续到 note 3（t=1500）。
    await tester.pump(const Duration(milliseconds: 500));
    injector.inject(_noteOn(notes[3].pitch));
    await tester.pump();

    final JudgmentStats s = state.controller.stats;
    expect(s.error, 1);
    expect(s.perfect, 4);
    expect(state.controller.phase, PlayerPhase.playing);
  });

  testWidgets('V3-D：导入 format2.mid → 抛 UnsupportedMidiFormatException 且 UI 弹窗提示',
      (WidgetTester tester) async {
    final Uint8List bytes = File('test_fixtures/format2.mid').readAsBytesSync();
    // 领域层异常。
    expect(
      () => MidiParser().parse(bytes),
      throwsA(isA<UnsupportedMidiFormatException>()),
    );

    // UI：转换页错误状态展示对应文案。
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final InMemoryFileSystemPort fs = InMemoryFileSystemPort();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          fileSystemProvider.overrideWithValue(fs),
          midiInputProvider.overrideWithValue(DebugMidiInjector.none()),
        ],
        child: const MaterialApp(home: ConvertPage()),
      ),
    );
    final ProviderContainer container = ProviderScope.containerOf(
      tester.element(find.byType(ConvertPage)),
    );
    await container.read(convertStateProvider.notifier).injectRawBytes(bytes);
    await tester.pumpAndSettle();
    expect(find.textContaining('格式 2'), findsWidgets);
  });

  testWidgets('V3-E：BPM 倍率 2.0 → 事件时间线 = 原 t × 0.5（误差 ≤ 1ms）',
      (WidgetTester tester) async {
    final DkScore score = _loadScore('simple_format0_8bars.mid');
    final DebugMidiInjector injector = DebugMidiInjector.none();
    final PlayerPageState state = await _pumpPlayer(
      tester,
      score: score,
      config: _config(mode: PlayMode.performance, bpm: 2.0),
      mode: PlayMode.performance,
      injector: injector,
    );

    // 实际经过 250ms → 播放时间线应为 500ms（t=500 的 note 触底）。
    await tester.pump(const Duration(milliseconds: 250));
    expect((state.controller.currentTimeMs - 500).abs(), lessThanOrEqualTo(1));

    // 此刻按下 pitch 62（t=500 的 note）应判 perfect。
    injector.inject(_noteOn(62));
    await tester.pump();
    final JudgmentStats s = state.controller.stats;
    expect(s.perfect, 1);
    expect(s.miss, 1); // t=0 的 note 已在 2x 时间线下掉 key
  });

  testWidgets('Stage7-场景3：学习模式演奏完成 → 返回库',
      (WidgetTester tester) async {
    final DkScore score = _loadScore('simple_format0_8bars.mid');
    final List<DkNote> notes = score.tracks.single.notes;
    final DebugMidiInjector injector = DebugMidiInjector.none();

    // 宿主页面 + 推入播放器。
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PlayerPage(
                        score: score,
                        config: _config(mode: PlayMode.learning),
                        midiInput: injector,
                        lifecycle: const _NoopLifecycle(),
                        initialMode: PlayMode.learning,
                      ),
                    ),
                  );
                },
                child: const Text('进入播放器'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('进入播放器'));
    await tester.pumpAndSettle();

    // 学习模式依次按对全部 note。
    injector.inject(_noteOn(notes[0].pitch));
    await tester.pump();
    for (var i = 1; i < notes.length; i++) {
      await tester.pump(const Duration(milliseconds: 500));
      injector.inject(_noteOn(notes[i].pitch));
      await tester.pump();
    }
    // 结束并出现结算页。
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('演奏完成'), findsOneWidget);

    // 返回库 → 回到宿主页面。
    await tester.tap(find.text('返回库'));
    await tester.pumpAndSettle();
    expect(find.text('进入播放器'), findsOneWidget);
    expect(find.text('演奏完成'), findsNothing);
  });
}
