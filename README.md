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
| Version | v1.0.0 - 初始可玩版本 |
| 规划阶段 | 问题清单已关闭，进入 Stage 拆分与设计 |
| 代码 | 暂未初始化 Flutter 工程（Stage 1 完成视觉原型后启动） |

## 目录结构

```
KeyDrop_Piano/
├── README.md                                # 本文件
├── Document/
│   ├── Agent开发规范.md                      # MainAgent / SubAgent 强制门禁
│   └── Update/
│       └── v1.0.0 - 初始可玩版本/
│           ├── 需求文档.md
│           ├── 问题清单.md
│           ├── 设计文档.md                   # Version 级设计
│           ├── 验收文档.md                   # Version 级验收
│           └── Stage1 - 视觉原型/
│               ├── 设计文档.md
│               └── 验收文档.md
├── app/                                     # Flutter 工程根目录（后续 Stage 创建）
└── ...
```

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
