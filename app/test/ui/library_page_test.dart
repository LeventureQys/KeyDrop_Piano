import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keydrop_piano/di/providers.dart';
import 'package:keydrop_piano/platform/debug/debug_midi_injector.dart';
import 'package:keydrop_piano/platform/debug/in_memory_fs_port.dart';
import 'package:keydrop_piano/ui/pages/library_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('空库显示导入引导', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          fileSystemProvider.overrideWithValue(InMemoryFileSystemPort()),
          midiInputProvider.overrideWithValue(DebugMidiInjector.none()),
        ],
        child: const MaterialApp(home: LibraryPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('还没有任何谱面'), findsOneWidget);
    expect(find.text('导入 MIDI 文件以创建第一个谱面'), findsOneWidget);
    expect(find.text('开始导入'), findsOneWidget);
  });

  testWidgets('有谱面时显示列表并可搜索', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          fileSystemProvider
              .overrideWithValue(InMemoryFileSystemPort.withSampleData()),
          midiInputProvider.overrideWithValue(DebugMidiInjector.none()),
        ],
        child: const MaterialApp(home: LibraryPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('致爱丽丝'), findsOneWidget);
    expect(find.text('小星星'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '致爱');
    await tester.pump();
    expect(find.text('致爱丽丝'), findsOneWidget);
    expect(find.text('小星星'), findsNothing);
  });

  testWidgets('空库点"开始导入"进入转换页', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          fileSystemProvider.overrideWithValue(InMemoryFileSystemPort()),
          midiInputProvider.overrideWithValue(DebugMidiInjector.none()),
        ],
        child: const MaterialApp(home: LibraryPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始导入'));
    await tester.pumpAndSettle();
    expect(find.text('谱面转换'), findsOneWidget);
  });
}
