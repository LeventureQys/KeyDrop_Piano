# KeyDrop_Piano（键落钢琴）

> 跨平台下落式钢琴学习软件 — 让用户先上车，后补票。

## 项目简介

KeyDrop_Piano 是一款"下落式钢琴学习辅助"应用。用户无需先掌握乐理知识，只需将电钢琴通过 USB OTG 连接到手机，App 即可读取 MIDI 文件、生成下落式谱面（DK 谱），并实时判定用户按键。可看作"音游 + 真实电钢琴 MIDI 输入"的结合。

## 目标平台

- **v1.0.0 仅交付 Android 单平台**（实际构建产物）
- iOS / Windows 在架构与代码组织上预留扩展能力，由后续 Version 接续

## 技术栈

| 层 | 技术 |
|---|---|
| UI 层 | Flutter + `CustomPainter` / `Ticker`（下落动画专用） |
| 领域层 | 纯 Dart（DK 谱模型、MIDI 解析、判定逻辑、统计） |
| 平台层 | Android：`android.media.midi` + MethodChannel/EventChannel |
| 构建 | Flutter SDK + Android Gradle |

> 关于"前后端"：本项目 v1.0.0 **无网络后端**，仅本地 App。Flutter 本身只是 UI/客户端框架，不存在"前后端分离"概念。需求文档中提到的"前台、后台形式"在本项目中解释为软件分层（UI 层 / 领域层 / 平台层）。

## 当前状态

| 项 | 状态 |
|---|---|
| Version | v1.0.1（v1.0.0 初始可玩版本的代码补完轮次，分支 `v1.0.1`） |
| 架构范式 | 三层（UI / Domain / Platform Adapter）+ 领域层零平台依赖，强制执行 |
| 核心闭环 | MIDI 导入 → DK 谱生成 → 横屏下落播放 → USB OTG 实时判定（学习/演奏双模式）→ 统计结算 → DK 谱导入导出 |
| 验证 | `flutter analyze` 0 问题、`flutter test` 全绿、分层检查通过、`integration_test` 5 场景（V3） |
| 真机验收 | 待用户配合（小米 17 Ultra + 电钢琴），见 `Stage7 .../真机验收指南.md` |

## 目录结构

```
KeyDrop_Piano/
├── README.md                                # 本文件
├── scripts/
│   └── check_layering.sh                    # 分层强制约束自检（验收 V1）
├── Document/
│   ├── Agent开发规范.md                      # MainAgent / SubAgent 强制门禁
│   └── Update/
│       └── v1.0.0 - 初始可玩版本/
│           ├── 需求文档.md
│           ├── 问题清单.md
│           ├── 设计文档.md                   # Version 级设计（含接口契约）
│           ├── 验收文档.md                   # Version 级验收（V1-V11）
│           └── Stage1 - 视觉原型/ ... Stage7 - 集成测试与收尾/
├── app/                                     # Flutter 工程
│   ├── lib/
│   │   ├── domain/                          # 领域层：模型 / 端口 / 服务 / 异常（纯 Dart）
│   │   ├── platform/                        # 平台层：android 适配器 + debug 测试钩子
│   │   ├── ui/                              # UI 层：页面 / 绘制器 / 通用控件
│   │   └── di/                              # Riverpod Provider 集中注册
│   ├── test/                                # 单元 + Widget 测试（与 lib 镜像结构）
│   ├── test_fixtures/                       # 验收文档 2.3 命名的 MIDI 与 golden DK 谱
│   ├── integration_test/                    # V3 端到端场景（DebugMidiInjector）
│   └── tool/                                # check_layering / gen_midi_fixtures
└── ...
```

## 快速验证（app/ 目录）

```bash
flutter pub get
flutter analyze                      # V4：0 问题
flutter test                         # V2：单元 + Widget 测试全绿
dart run tool/check_layering.dart    # F-01：领域层零平台依赖
flutter build apk --debug            # 产物：build/app/outputs/flutter-apk/app-debug.apk
flutter test integration_test/       # V3：需已连接 Android 设备/模拟器
```

> 构建环境：Flutter 3.x stable + JDK 21 + Android SDK（platform 36 / build-tools 34+36 / NDK 27.0.12077973）。Gradle 依赖与 SDK 组件下载走代理时，在 `android/gradle.properties` 配置 `systemProp.http(s).proxyHost/Port`。

## 开发流程

本项目严格遵循 [Document/Agent开发规范.md](Document/Agent开发规范.md)：

1. **问题清单先行**：每个 Version / Stage 开发前必须建立 `问题清单.md`，所有不确定点关闭后才能进入设计。
2. **零上下文文档**：设计文档与验收文档必须让全新 Agent 在无对话历史的情况下独立开发或验收。
3. **Stage 串行 + SubStage 可并行**：Stage 间按依赖关系串行执行，Stage 内部 SubStage 之间无开发依赖。
4. **强制门禁**：未关闭问题清单 / 无验收文档 → 禁止进入开发或验收。

## v1.0.0 核心范围（一句话）

> MIDI 文件导入 → DK 谱生成 → 横屏下落式播放 → 电钢琴 USB OTG MIDI 实时输入 → 学习/演奏双模式 → 抢/拖/掉 key 统计 → DK 谱本地导入导出。

不包含：蓝牙 MIDI、Wi-Fi MIDI、iOS/Windows 构建、云账号、社区分享、手位识别、长按判定。

## 文档导航

- [需求文档](Document/Update/v1.0.0%20-%20初始可玩版本/需求文档.md)
- [问题清单](Document/Update/v1.0.0%20-%20初始可玩版本/问题清单.md)
- [Version 设计文档](Document/Update/v1.0.0%20-%20初始可玩版本/设计文档.md)
- [Version 验收文档](Document/Update/v1.0.0%20-%20初始可玩版本/验收文档.md)
- [Agent 开发规范](Document/Agent开发规范.md)
