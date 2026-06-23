# KeyDrop_Piano v1.0.0 用户流程图

> 本文档以 Mermaid `flowchart` 描述 v1.0.0 视觉原型的 6 条关键用户路径,所有节点引用 SubStage 1.1 / 1.2 / 1.3 的真实元素编号 (LIB-* / SET-* / CVT-* / PLY-*)。
>
> 元素编号定义见各页面 HTML 文件底部 `========== 元素清单 ==========` 注释块。

---

## 1. 首次使用流程 (空库 → 导入 MIDI → 首次播放)

```mermaid
flowchart TD
    A([启动 App]) --> B{库内有谱?}
    B -- 否 --> C["谱面库 · 空库状态<br/>LIB-04 插画 / LIB-05 主提示<br/>LIB-06 副提示"]
    C --> D["LIB-07 空库导入按钮<br/>或 LIB-17 FAB +"]
    D --> E["LIB-18 从 MIDI 文件创建"]
    E --> F["转换页状态 A<br/>CVT-A1 选择 MIDI 文件 大按钮"]
    F --> G["转换页状态 B · 已选文件<br/>CVT-B1 文件 banner<br/>CVT-B3 轨道列表行 ×3"]
    G --> H["CVT-B4 轨道单选 radio<br/>(选定旋律轨)"]
    H --> I["CVT-B6 下一步:预览 按钮"]
    I --> J["转换页状态 C · 预览<br/>CVT-C1 曲名输入框<br/>CVT-C7 8 拍下落预览缩略图"]
    J --> K["CVT-C9 下一步:保存 按钮"]
    K --> L["转换页状态 D · 保存<br/>CVT-D1 文件名输入框"]
    L --> M["CVT-D4 确认保存 按钮"]
    M --> N["CVT-D5 已保存 toast (1s)"]
    N --> O["谱面库 · 有谱状态<br/>LIB-10 谱面列表项 (新增)"]
    O --> P["点击列表项 → 播放器<br/>PLY-01 屏幕容器"]
```

说明:首次启动 App 时,谱面库处于空库状态 (`LIB-04`/`LIB-05`/`LIB-06`),引导用户通过 `LIB-07` 或 `LIB-17` FAB 进入转换页。转换页依次经历 `CVT-A1 → CVT-B6 → CVT-C9 → CVT-D4` 四个关键操作,最后通过 `CVT-D5` toast 反馈,自动回到谱面库列表 (`LIB-10`)。

---

## 2. 日常使用流程 (有谱库 → 选谱 → 播放 → 结算)

```mermaid
flowchart TD
    A([启动 App]) --> B["谱面库 · 有谱状态<br/>LIB-08 搜索框 / LIB-09 搜索结果计数"]
    B -- 输入关键字 --> B
    B --> C["LIB-10 谱面列表项 (单击)"]
    C --> D{用户希望进入哪种模式?}
    D -- 学习模式 --> E1["播放器 · 状态 1 学习等待<br/>PLY-10 模式切换 pill = 学习<br/>PLY-20 下落 key (停在判定线上方)"]
    D -- 演奏模式 --> E2["播放器 · 状态 3 演奏推进<br/>PLY-10 模式切换 pill = 演奏<br/>PLY-11~15 实时统计动态递增"]
    E1 --> F["PLY-40 循环下落动画<br/>(234 px/s, 4s 循环)"]
    E2 --> F
    F --> G["演奏结束"]
    G --> H["播放器 · 状态 5 结算页<br/>PLY-35 结算视图<br/>PLY-36 综合得分 / PLY-37 五项明细"]
    H --> I{用户选择}
    I -- PLY-38 再来一次 --> E1
    I -- PLY-39 返回库 --> B
```

说明:有谱情况下,通过 `LIB-08` 搜索过滤或直接点击 `LIB-10`,通过 `PLY-10` 模式 pill 切换学习/演奏。学习模式下 `PLY-20` 下落 key 会在判定线上方等待;演奏模式下 `PLY-11`~`PLY-15` 统计字段实时递增。结算页通过 `PLY-36` 显示综合得分,`PLY-38` / `PLY-39` 决定下一步。

---

## 3. 学习模式判定状态机

```mermaid
flowchart TD
    S([进入学习模式<br/>PLY-10 = 学习]) --> W["等待按键状态<br/>PLY-20 触底 key 静止<br/>PLY-19 判定线 y=432"]
    W --> E{用户输入}
    E -- 按对目标键 --> R1["键位绿色高亮 200ms<br/>PLY-23 white-key 绿色态<br/>PLY-21 触底 ripple"]
    E -- 按错其他键 --> R2["状态 2 · 错音反馈<br/>PLY-26 整屏错音脉冲 300ms<br/>PLY-23/24 键位红色高亮 500ms<br/>PLY-15 实时统计-错 +1"]
    E -- 长时间未按 --> W
    R1 --> N["前进到下一个 key"]
    R2 --> W
    N --> W
    W --> P{暂停?}
    P -- 是 PLY-16 --> PM["状态 4 · 暂停遮罩<br/>PLY-31 / PLY-32 继续<br/>PLY-33 重新开始 / PLY-34 退出"]
    PM -- PLY-32 继续 --> W
```

说明:学习模式核心特征是"按对前进、按错停留 + 闪红"。错音视觉反馈对应 `PLY-26`(整屏脉冲)+ `PLY-23` / `PLY-24` (键位红色高亮)+ `PLY-15` 错音统计自增。暂停由 `PLY-16` 触发遮罩 `PLY-31`,内含三按钮 `PLY-32` / `PLY-33` / `PLY-34`。

---

## 4. 演奏模式判定状态机

```mermaid
flowchart TD
    S([进入演奏模式<br/>PLY-10 = 演奏]) --> T["时间线推进<br/>PLY-40 循环下落动画 234 px/s<br/>PLY-08 小节计数滚动"]
    T --> J{key 到达判定线 PLY-19}
    J -- 用户在窗口内按下 --> H["判定为命中"]
    J -- 用户未按下 --> M["PLY-14 实时统计-掉 +1"]
    H --> CL{延迟分类}
    CL -- 误差 ≤ 严判定 --> P["PLY-11 完美 +1"]
    CL -- 提前 --> R["PLY-12 抢 +1"]
    CL -- 滞后 --> L["PLY-13 拖 +1"]
    P --> RP["PLY-21 触底 ripple 200ms<br/>PLY-24 黑键紫态 / PLY-23 白键蓝态"]
    R --> RP
    L --> RP
    M --> T
    RP --> T

    %% 任意时刻按错其他键独立计入 ErrorCount
    T -.->|按错任意非目标键| EE["PLY-15 实时统计-错 +1<br/>PLY-26 整屏脉冲 300ms"]
    EE -.-> T
```

说明:演奏模式不停止时间线,key 自动消失。命中后细分为 `PLY-11 完美 / PLY-12 抢 / PLY-13 拖`,未按下计入 `PLY-14 掉`,按错任意非目标键独立计入 `PLY-15 错` 并触发 `PLY-26` 整屏脉冲。所有命中触发 `PLY-21` 触底 ripple 视觉反馈。

---

## 5. MIDI 导入失败流程 (异常处理)

```mermaid
flowchart TD
    A["谱面库 · 任意状态"] --> B["LIB-17 FAB +<br/>→ LIB-18 从 MIDI 文件创建"]
    B --> C["转换页状态 A<br/>CVT-A1 选择 MIDI 文件 大按钮"]
    C --> D{解析 MIDI 文件}
    D -- 成功 SMF 0/1 --> OK["转换页状态 B (正常流程)"]
    D -- 失败 SMF 格式 2 --> E1["状态 E · 异常 modal<br/>CVT-E1 modal 背景<br/>CVT-E2 标题: 无法导入<br/>CVT-E3 单选 = format2<br/>CVT-E4 文案: 此文件为 SMF 格式 2..."]
    D -- 失败 chunk 损坏 --> E2["状态 E · 异常 modal<br/>CVT-E1 modal 背景<br/>CVT-E3 单选 = corrupted<br/>CVT-E4 文案: 文件已损坏..."]
    E1 --> K["CVT-E5 知道了 按钮"]
    E2 --> K
    K --> C
```

说明:MIDI 解析失败有两种典型错误 (SMF 格式 2 / chunk header 损坏),都由 `CVT-E1` 异常 modal 承载,通过 `CVT-E3` 单选按钮在原型中切换显示哪条文案 (`CVT-E4`),`CVT-E5` 知道了按钮关闭弹窗回到状态 A 重新选文件。

---

## 6. 谱面导入导出流程 (SAF 与 DK 谱)

```mermaid
flowchart TD
    L["谱面库 · 有谱状态<br/>LIB-10 谱面列表项"] --> P{用户意图}
    P -- 长按列表项 600ms --> M["LIB-16 长按上下文菜单<br/>(演奏 / 重命名 / 导出 / 删除)"]
    P -- 点击 LIB-17 FAB --> F["FAB 展开<br/>LIB-18 从 MIDI / LIB-19 导入 DK 谱"]

    M -- 选 导出 --> EX["调用 SAF<br/>console.log: action: export"]
    M -- 选 演奏 --> PL["跳转播放器<br/>PLY-01 屏幕容器"]
    M -- 选 重命名 --> RN["弹出重命名输入"]
    M -- 选 删除 --> DL["二次确认 → 移除"]

    F -- LIB-18 从 MIDI 文件创建 --> CV["转换页 CVT-* 流程"]
    F -- LIB-19 导入 DK 谱 --> SAF["调用 SAF 选 .dkscore<br/>console.log: nav: import-dk"]
    SAF --> AppendLib["加入库列表 LIB-10"]
    CV --> AppendLib
    EX --> SafOut([SAF 系统对话框 - 选择输出位置])
    AppendLib --> L
```

说明:导入导出统一走 Android SAF (Storage Access Framework)。`LIB-16` 长按菜单提供单条目操作 (含导出),`LIB-17` FAB 提供两种导入入口:`LIB-18` 从 MIDI 创建 (走 `CVT-*` 转换流程) 与 `LIB-19` 直接导入 DK 谱 (走 SAF 文件选择)。所有新增谱面最终都回流到 `LIB-10` 列表项中。

---

## 元素编号速查 (按页面)

| 页面 | 编号区间 | 文件 |
|---|---|---|
| 谱面库 | `LIB-01` ~ `LIB-20` | `pages/library.html` |
| 设置 | `SET-01` ~ `SET-15` | `pages/settings.html` |
| 转换页 | `CVT-01` ~ `CVT-05` (通用) / `CVT-A1`~`CVT-A2` / `CVT-B1`~`CVT-B6` / `CVT-C1`~`CVT-C9` / `CVT-D1`~`CVT-D5` / `CVT-E1`~`CVT-E5` | `pages/convert.html` |
| 播放器 | `PLY-01` ~ `PLY-40` | `pages/player.html` |

设置页编号 (`SET-01` ~ `SET-15`) 主要服务"调参"路径,不在上述 6 个主流程中,但任何流程都可由 `LIB-02` 设置入口侧向跳转 (例如:`LIB-02 → SET-06` 下落时长滑条 → 返回 `LIB-10` 重新选谱)。
