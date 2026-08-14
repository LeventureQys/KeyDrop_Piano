import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keydrop_piano/di/providers.dart';
import 'package:keydrop_piano/domain/ports/file_system_port.dart';
import 'package:keydrop_piano/platform/debug/debug_midi_injector.dart';
import 'package:keydrop_piano/platform/debug/in_memory_fs_port.dart';
import 'package:keydrop_piano/ui/pages/convert_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late InMemoryFileSystemPort fs;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    fs = InMemoryFileSystemPort();
  });

  Future<ProviderContainer> pumpConvert(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          fileSystemProvider.overrideWithValue(fs),
          midiInputProvider.overrideWithValue(DebugMidiInjector.none()),
        ],
        child: const MaterialApp(home: ConvertPage()),
      ),
    );
    return ProviderScope.containerOf(
      tester.element(find.byType(ConvertPage)),
    );
  }

  testWidgets('转换流程：注入字节 → 选轨 → 预览 → 保存到谱面库', (WidgetTester tester) async {
    final ProviderContainer container = await pumpConvert(tester);
    final Uint8List bytes =
        File('test/fixtures/f0_cmajor_scale.mid').readAsBytesSync();

    // A → B：解析成功进入选轨（compute 用真实 isolate，须在 runAsync 中执行）。
    await tester.runAsync(() async {
      await container.read(convertStateProvider.notifier).injectRawBytes(bytes);
    });
    await tester.pump();
    expect(find.textContaining('轨道 1'), findsOneWidget);

    // B → C：点选轨道。
    await tester.tap(find.textContaining('轨道 1'));
    await tester.pump();
    expect(find.text('下一步：保存'), findsOneWidget);

    // C → D：预览页点下一步。
    await tester.tap(find.text('下一步：保存'));
    await tester.pump();
    expect(find.text('💾 保存为 DK 谱'), findsOneWidget);

    // 输入曲名并保存。
    await tester.enterText(find.byType(TextField).last, '测试谱 1');
    await tester.tap(find.text('确认保存'));
    await tester.pumpAndSettle();

    // 谱面库（内存 FS）出现新文件。
    final List<DkScoreFile> files = await fs.listDkScores();
    expect(files.length, 1);
    expect(files.first.displayName, '测试谱 1');
    final String content = await fs.readDkScore(files.first.fileId);
    expect(content, contains('"dkVersion": "1.0"'));
  });

  testWidgets('错误路径：格式 2 文件 → eError 显示提示文案', (WidgetTester tester) async {
    final ProviderContainer container = await pumpConvert(tester);
    final Uint8List bytes =
        File('test/fixtures/format2.mid').readAsBytesSync();

    await tester.runAsync(() async {
      await container.read(convertStateProvider.notifier).injectRawBytes(bytes);
    });
    await tester.pump();
    expect(find.text('无法导入'), findsOneWidget);
    expect(find.textContaining('格式 2'), findsWidgets);

    // 知道了 → 回到初始状态。
    await tester.tap(find.text('知道了'));
    await tester.pump();
    expect(find.text('📁 选择 MIDI 文件'), findsOneWidget);
  });

  testWidgets('错误路径：损坏文件 → 显示损坏提示', (WidgetTester tester) async {
    final ProviderContainer container = await pumpConvert(tester);
    final Uint8List bytes =
        File('test/fixtures/corrupted.mid').readAsBytesSync();

    await tester.runAsync(() async {
      await container.read(convertStateProvider.notifier).injectRawBytes(bytes);
    });
    await tester.pump();
    expect(find.text('无法导入'), findsOneWidget);
    expect(find.textContaining('损坏'), findsWidgets);
  });
}
