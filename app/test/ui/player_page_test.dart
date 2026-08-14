import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keydrop_piano/domain/models/app_config.dart';
import 'package:keydrop_piano/domain/models/dk_score.dart';
import 'package:keydrop_piano/domain/ports/lifecycle_port.dart';
import 'package:keydrop_piano/domain/ports/midi_input_port.dart';
import 'package:keydrop_piano/platform/debug/debug_midi_injector.dart';
import 'package:keydrop_piano/ui/pages/player_controller.dart';
import 'package:keydrop_piano/ui/pages/player_page.dart';

class _NoopLifecycle implements LifecyclePort {
  const _NoopLifecycle();

  @override
  Future<void> setKeepScreenOn(bool enabled) async {}
}

DkScore _score() => const DkScore(
      dkVersion: '1.0',
      meta: DkMeta(
        title: '测试曲',
        composer: '测试者',
        sourceMidiSha256: 'abc',
        bpmBase: 120,
        timeSignature: '4/4',
        keySignature: 'C',
        totalDurationMs: 1500,
      ),
      tracks: <DkTrack>[
        DkTrack(
          id: 'main',
          notes: <DkNote>[
            DkNote(t: 0, d: 300, pitch: 60, velocity: 80),
            DkNote(t: 500, d: 300, pitch: 62, velocity: 80),
            DkNote(t: 1000, d: 300, pitch: 64, velocity: 80),
          ],
        ),
      ],
      tempoMap: <DkTempoEvent>[
        DkTempoEvent(t: 0, bpm: 120),
      ],
    );

MidiEvent _noteOn(int pitch) => MidiEvent(
      type: MidiEventType.noteOn,
      channel: 0,
      pitch: pitch,
      velocity: 100,
      controllerNumber: 0,
      controllerValue: 0,
      timestampUs: 0,
    );

void main() {
  testWidgets('播放器信息栏展示曲名/BPM/拍号/调号/模式/设备状态', (WidgetTester tester) async {
    final DebugMidiInjector injector = DebugMidiInjector.none();
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerPage(
          score: _score(),
          config: AppConfig.defaults.copyWith(defaultMode: PlayMode.learning),
          midiInput: injector,
          lifecycle: const _NoopLifecycle(),
          initialMode: PlayMode.learning,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('测试曲'), findsOneWidget);
    expect(find.text('120'), findsOneWidget); // BPM
    expect(find.text('4/4'), findsOneWidget); // 拍号
    expect(find.text('C'), findsOneWidget); // 调号
    expect(find.text('学习'), findsOneWidget); // 模式标签
    expect(find.text('Debug Injector'), findsOneWidget); // 注入器设备名
  });

  testWidgets('学习模式：按错音红色反馈并等待，按对后继续，结束显示结算', (WidgetTester tester) async {
    final DebugMidiInjector injector = DebugMidiInjector.none();
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerPage(
          score: _score(),
          config: AppConfig.defaults.copyWith(defaultMode: PlayMode.learning),
          midiInput: injector,
          lifecycle: const _NoopLifecycle(),
          initialMode: PlayMode.learning,
        ),
      ),
    );
    await tester.pump();
    final PlayerPageState state =
        tester.state<PlayerPageState>(find.byType(PlayerPage));

    // note 0（t=0，pitch 60）。
    injector.inject(_noteOn(60));
    await tester.pump();
    expect(state.controller.stats.perfect, 1);

    // note 1（t=500，pitch 62）：先按错 99。
    await tester.pump(const Duration(milliseconds: 500));
    injector.inject(_noteOn(99));
    await tester.pump();
    expect(state.controller.stats.error, 1);
    expect(state.controller.phase, PlayerPhase.playing); // 卡住等待

    // 按对 → 继续。
    injector.inject(_noteOn(62));
    await tester.pump();
    expect(state.controller.stats.perfect, 2);

    // note 2（t=1000，pitch 64）。
    await tester.pump(const Duration(milliseconds: 500));
    injector.inject(_noteOn(64));
    await tester.pump();

    // 全部判定 → 学习模式结束 → 结算页。
    await tester.pump(const Duration(milliseconds: 100));
    expect(state.controller.phase, PlayerPhase.finished);
    expect(find.text('演奏完成'), findsOneWidget);
    // 3 完美 + 1 错音 → (3*100)/4 = 75.0%。
    expect(find.text('75.0%'), findsOneWidget);

    // 冲刷高亮定时器，避免测试结束时有 pending timer。
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('暂停遮罩：继续 / 重新开始 / 退出', (WidgetTester tester) async {
    final DebugMidiInjector injector = DebugMidiInjector.none();
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerPage(
          score: _score(),
          config: AppConfig.defaults.copyWith(defaultMode: PlayMode.performance),
          midiInput: injector,
          lifecycle: const _NoopLifecycle(),
          initialMode: PlayMode.performance,
        ),
      ),
    );
    await tester.pump();
    final PlayerPageState state =
        tester.state<PlayerPageState>(find.byType(PlayerPage));

    // 暂停。
    await tester.tap(find.byIcon(Icons.pause));
    await tester.pump();
    expect(find.text('继续'), findsOneWidget);
    expect(find.text('重新开始'), findsOneWidget);
    expect(find.text('退出'), findsOneWidget);

    // 继续。
    await tester.tap(find.text('继续'));
    await tester.pump();
    expect(state.controller.phase, PlayerPhase.playing);
    expect(find.text('继续'), findsNothing);

    // 推进到演奏结束并冲刷掉键高亮定时器（避免 pending timer）。
    await tester.pump(const Duration(milliseconds: 4000));
    expect(state.controller.phase, PlayerPhase.finished);
    await tester.pump(const Duration(milliseconds: 300));
  });
}
