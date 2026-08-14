# KeyDrop_Piano（键落钢琴）— app/

下落式钢琴学习 App 的 Flutter 工程（Android 单平台，v1.0.1）。

## 架构（Version 设计文档 2.1 三层）

```
lib/
├── main.dart / app.dart      # 入口：强制横屏 + MaterialApp
├── domain/                   # 领域层（纯 Dart，零平台依赖，禁止 import flutter）
│   ├── models/               # DkScore/DkMeta/DkTrack/DkNote/DkTempoEvent/AppConfig/MidiData
│   ├── ports/                # MidiInputPort/FileSystemPort/ConfigRepositoryPort/LifecyclePort
│   ├── services/             # MidiParser/DkGenerator/JudgmentEngine/StatisticsAggregator/BpmScaler
│   └── exceptions/           # DkException 体系
├── platform/                 # 平台层
│   ├── android/              # MethodChannel/EventChannel 适配器 + Kotlin 插件（android/ 目录）
│   └── debug/                # DebugMidiInjector / InMemoryFileSystemPort（测试钩子）
├── ui/                       # UI 层：pages / painters / widgets
└── di/providers.dart         # Riverpod Provider 集中注册
```

- **分层门禁**：`dart run tool/check_layering.dart`（领域层 import 黑名单）；
  仓库根目录另有 `scripts/check_layering.sh`（验收 V1）。
- **状态管理**：仅 `flutter_riverpod`。
- **动画**：下落区/键盘全部 `CustomPainter` + `Ticker`，禁止 Widget 树动画（F-04）。
- **MIDI 解析**：`compute` 后台 isolate（F-05）。

## 常用命令

```bash
flutter pub get
flutter analyze                       # 0 问题
flutter test                          # 单元 + Widget 测试
dart run tool/check_layering.dart     # 分层自检
dart run tool/gen_midi_fixtures.dart  # 重新生成 test/fixtures 与 test_fixtures
flutter test integration_test/        # V3 场景（需设备/模拟器）
flutter build apk --debug             # 产物 build/app/outputs/flutter-apk/app-debug.apk
```

## 构建环境

- Flutter 3.x stable（Dart 3.x）
- JDK 21
- Android SDK：platforms;android-36、build-tools;34.0.0+36.0.0、platform-tools、
  NDK 27.0.12077973（sdkmanager 安装并接受 license）
- Gradle 走代理时配置 `android/gradle.properties` 的 `systemProp.*.proxyHost/Port`

## 关键实现说明（对照 v1.0.0 设计文档）

- **MIDI 输入链路**：`MidiInputPlugin.kt`（MidiManager.openDevice → MidiInputPort.connect(MidiReceiver)）
  → 每条消息 11 字节包（status/data1/data2/timestampUs BE）→ EventChannel
  `keydrop_piano/midi_events` → `AndroidMidiInputAdapter`（256 事件队列）。
- **判定**：`delta = 按下时刻 - (触底时刻 + inputLatencyOffsetMs)`；
  学习模式 key 停在判定线等待（时间线吸附 `t + offset`）、错音红框脉冲 + 键位红 0.5s；
  演奏模式按时间线推进并记掉 key；和弦同 t 不同 pitch 独立判定（F4）。
- **BPM 倍率**：0.5x-2.0x 只缩放时间线（V3-E：2.0x 时事件时刻 = 原 t × 0.5）。
- **文件系统**：`FileSystemPlugin.kt`（getExternalFilesDir 私有目录 + SAF 导入导出
  + `readMidiFile` 读取临时 MIDI 字节 + `importDkScore` 导入外部 DK 谱，V9）。
- **屏幕常亮**：播放器进入/离开经 `keydrop_piano/lifecycle` 通道控制
  `FLAG_KEEP_SCREEN_ON`；横屏由 `SystemChrome.setPreferredOrientations` +
  Manifest `screenOrientation="landscape"` 双保险。
