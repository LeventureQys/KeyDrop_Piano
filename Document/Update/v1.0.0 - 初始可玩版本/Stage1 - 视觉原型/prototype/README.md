# KeyDrop_Piano v1.0.0 视觉原型

> **这是什么**:KeyDrop_Piano (键落钢琴) Android 下落式钢琴学习软件 **v1.0.0 的视觉原型**,用纯 HTML + Tailwind CDN + 原生 JS 制作。它**不是 Flutter 代码**,目的是让用户在浏览器中真正点击、看到下落动画的节奏感,在进入 Flutter 主体开发前冻结 UI 决策。
>
> 原型代码丢弃即可,不影响 Flutter 主代码库。

---

## 1. 如何打开

原型屏幕固定为 `1200×540` (模拟横屏 2400×1080 手机,1:2 缩放)。**建议在桌面浏览器最大化窗口下查看**。

### 方式 1 (推荐):本地 HTTP 服务器

最稳定,所有浏览器都能正常加载 iframe 子页。

```bash
cd "prototype"
python -m http.server 8000
# 然后浏览器访问 http://localhost:8000/
```

若没有 Python,可改用任意静态服务器,例如:

```bash
npx http-server -p 8000   # 需 Node.js
# 或者 VS Code 的 Live Server 插件
```

### 方式 2:直接双击 `index.html`

```
双击 prototype/index.html
```

**注意事项**:

- 首次打开需联网,Tailwind 通过 CDN 加载:`https://cdn.tailwindcss.com`
- 部分浏览器在 `file://` 协议下对同源 iframe 加载有限制 (例如较严格的安全策略),可能导致 `index.html` 中的子页 iframe 加载失败 (显示空白)
- 若方式 2 失败,有两个回退选项:
  1. 改用方式 1 (本地 HTTP 服务器),即可解决
  2. 直接双击 `pages/*.html` 中的任意一个文件,每个子页都是自包含的,可独立工作

---

## 2. 联网要求

| 资源 | 用途 | URL |
|---|---|---|
| Tailwind CSS | 所有页面的 CSS 框架 | `https://cdn.tailwindcss.com` |

**首次打开必须联网**,浏览器会缓存 CDN 资源,后续离线打开也能工作 (取决于浏览器缓存策略)。

---

## 3. 目录结构

```
prototype/
├── README.md              # 本文件 (SubStage 1.4 产出)
├── index.html             # 主入口: tabs + iframe (SubStage 1.4 产出)
├── user_flow.md           # 用户流程图 6 张 Mermaid (SubStage 1.4 产出)
├── shared/
│   └── styles.css         # 公共 CSS 变量 (SubStage 1.4 产出, 仅 index.html 用)
└── pages/
    ├── library.html       # 谱面库页    (SubStage 1.1 产出)
    ├── settings.html      # 设置页      (SubStage 1.1 产出)
    ├── convert.html       # MIDI 转换页 (SubStage 1.2 产出)
    └── player.html        # 播放器页    (SubStage 1.3 产出)
```

---

## 4. 页面清单与说明

每个子页都是**自包含 HTML 文件** (内联 Tailwind CDN + style + script),既可在主入口 iframe 中查看,也可单独双击查看。

| 页面 | 文件 | SubStage | 一句话说明 |
|---|---|---|---|
| 谱面库 | `pages/library.html` | 1.1 | 含两种状态:空库引导导入 / 有谱列表 (≥5 条 mock),右下角 FAB,长按 600ms 弹出菜单 |
| 设置 | `pages/settings.html` | 1.1 | 5 个分组,所有 AppConfig 字段可调,屏幕底部实时显示当前 JSON |
| 转换页 | `pages/convert.html` | 1.2 | MIDI 导入向导,含 4 个状态 (A 未选 / B 多轨 / C 预览 / D 保存) + E 异常弹窗 |
| 播放器 | `pages/player.html` | 1.3 | 含 5 个状态 (学习等待 / 学习按错 / 演奏推进 / 暂停 / 结算) + 循环下落动画 234 px/s |

---

## 5. 状态切换说明 (原型调试用)

每个子页**右上角都有"原型调试用"状态切换栏**,用于在浏览器中观察不同状态视觉:

| 子页 | 状态切换栏 | 切换内容 |
|---|---|---|
| `library.html` | `[空库 / 有谱]` 双按钮 | 在 A 空库 / B 有谱 之间切换 |
| `settings.html` | (无,单状态视图) | 只有一种状态,所有控件实时联动 JSON 预览 |
| `convert.html` | `[A][B][C][D][E]` 五按钮 | A 未选 / B 多轨 / C 预览 / D 保存 / E 异常 |
| `player.html` | `[1][2][3][4][5]` 五按钮 + `[模拟按对][模拟按错]` | 1 学习等待 / 2 学习按错 / 3 演奏推进 / 4 暂停 / 5 结算 |

---

## 6. 主入口 `index.html` 操作要点

- **顶部 tabs**:`谱面库 / 设置 / 转换页 / 播放器` 点击切换 iframe 的 `src`
- **重新加载按钮**:右上角 `🔄 重新加载`,用于强制刷新当前 iframe (重新触发循环下落动画 / toast 等)
- **手机屏幕外框**:iframe 周围一圈深色装饰 (圆角 + 阴影),便于在桌面浏览器中识别"这是手机屏幕模拟"
- **URL hash 路由**:切换 tab 会同步 `#library` / `#settings` / `#convert` / `#player`,刷新或分享链接时可保留位置

---

## 7. 已知边界与说明

| 项 | 说明 |
|---|---|
| 浏览器目标 | Chromium 120+ / Edge 120+ / Firefox 120+ |
| 离线模式 | 首次加载需联网拉 Tailwind CDN,缓存后可在大多数浏览器中离线打开 |
| 滚动 | 在 `1200px` 宽度以下的窗口中,主入口会出现横向滚动条以查看完整宽度 (符合"屏幕固定 1200×540"的原型约束) |
| **播放器循环动画约束** | 在 SubStage 1.3 的播放器循环动画中,**最后一个 note (C5) 因 4 秒循环约束未能完整下落到底**。这是 mock 8 拍数据 (`t = 0, 500, 1000, 1500, 2000, 2500, 3000, 3500ms`) 在 `MOCK_LOOP_DURATION_MS = 4000` 循环下的可接受表现,由设计文档约束 (见设计文档 4.4 节 mock 数据约定 + 3.3 节 SubStage 1.3 任务书)。**这是预期行为,不是 bug**。 |
| 调试栏不是正式 UI | 每个子页右上角的状态切换栏标注"原型调试用",在 Flutter 主开发中将被移除,不应被视为最终 UI 组件 |

---

## 8. 进一步阅读

- 用户流程图 (含 6 张 Mermaid):见 [`user_flow.md`](./user_flow.md)
- 各子页元素清单:见各 `pages/*.html` 文件底部 `========== 元素清单 ==========` 注释块
- Stage 1 设计文档:见 `../设计文档.md`

---

**当前版本**:KeyDrop_Piano v1.0.0 · Stage 1 视觉原型
