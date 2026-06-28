# 05 — 灵动岛窗口（NSPanel）

> 目标：创建 macOS 顶部 Notch / 浮动胶囊窗口，支持 compact / pill / expanded 三种形态。

---

## 需求对齐

本阶段对应 `demand.md` 的 3.4 灵动岛窗口。

05 负责：

- 使用 AppKit `NSPanel` 创建无边框、不抢焦点的顶部窗口
- 动态计算刘海区域；无刘海设备降级为顶部居中浮动胶囊
- 优先显示在内置屏幕，避免外接显示器成为主屏时窗口跑偏
- 支持 `compact` / `pill` / `expanded` 三种窗口形态
- Hover 时向下展开，移开后收回
- 监听屏幕参数变化并重新定位
- 根据 04 的 `EventBus.sessionState` 切换 compact / pill 形态
- 提供 05 范围内的基础占位内容

05 不负责：

- 像素宠物动画和素材（06）
- Token 数字展示、卡片、历史折线图（07）
- 等待回复红色脉冲、通知、一键唤起 Codex（08）
- Rust sidecar 到 Swift UI 的 IPC 端到端集成（09）

---

## 当前实现文件

```text
CodexIsland/App/
├── AppDelegate.swift
└── main.swift

CodexIsland/UI/NotchWindow/
├── IslandShape.swift
├── NotchIslandPanel.swift
└── NotchIslandView.swift
```

`main.swift` 使用 AppKit 主入口显式运行 `NSApplication.shared.run()`。这是为了让 `LSUIElement` 菜单栏应用稳定常驻，同时继续保留 01 的 `NSStatusItem`。

---

## 窗口形态

`IslandShape.swift` 定义：

| 形态 | 尺寸 | 说明 |
|------|------|------|
| `compact` | 动态贴合刘海；无刘海 fallback `120×34` | Idle / Error |
| `pill` | `360×34`，高度会随刘海高度抬升 | Thinking / Streaming / AwaitingInput |
| `expanded` | `360×280` | Hover 展开 |

Compact 的宽高来自刘海 frame；无刘海设备使用顶部居中 fallback。

---

## NSPanel 行为

`NotchIslandPanel.swift` 已实现：

- `styleMask = [.borderless, .nonactivatingPanel]`
- `level = statusWindow + 1`
- `backgroundColor = .clear`
- `isOpaque = false`
- `hasShadow = false`
- `hidesOnDeactivate = false`
- `collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]`
- `canBecomeKey = false`
- `canBecomeMain = false`
- `acceptsMouseMovedEvents = true`

窗口内容由 `NotchIslandHostingView` 承载。Hover 不依赖 SwiftUI `.onHover`，而是使用 AppKit `NSTrackingArea` 处理 `mouseEntered` / `mouseExited`，并在退出时延迟校验真实鼠标位置，避免窗口动画变形时误触发收起。

---

## 刘海与屏幕定位

屏幕选择逻辑：

1. 优先选择 `CGDisplayIsBuiltin == true` 的内置屏幕
2. 如果未找到内置屏幕，选择存在 `auxiliaryTopLeftArea` / `auxiliaryTopRightArea` 的屏幕
3. 最后 fallback 到 `NSScreen.main`

刘海计算逻辑：

- 有刘海：使用 `auxiliaryTopLeftArea.width` 和 `auxiliaryTopRightArea.width` 推导中间刘海宽度
- 刘海高度：优先从顶部安全区域动态推导，异常时 fallback `34pt`
- 无刘海：使用顶部居中 `120×34` 虚拟胶囊
- 所有形态都以刘海中心点为锚点，并 clamp 到目标屏幕范围内

---

## SwiftUI 内容边界

`NotchIslandView.swift` 只实现 05 的基础承载内容：

- Compact：状态圆点
- Pill：状态圆点 + 简短状态文字
- Expanded：状态标题、状态副文案、Session 基础信息

当前没有实现：

- 宠物渲染
- Token 四格卡片
- 历史折线图
- 等待状态红色强提示
- 通知和 Codex 唤起按钮

---

## App 接入

`AppDelegate.applicationDidFinishLaunching` 当前执行：

```swift
NSApp.setActivationPolicy(.accessory)
setupStatusItem()
NotchIslandPanel.shared.show()
```

Rust sidecar 启动和 Swift IPC 连接仍保留给 09。

---

## 验证记录

构建验证：

```text
xcodegen generate: passed
cargo test: 20 passed
xcodebuild Debug build: BUILD SUCCEEDED
make verify: passed
```

运行时窗口验证：

```text
open -n CodexIsland.app: app process stays alive
compact frame: 120×34 at top center
hover frame: 360×280
after mouse leave: 120×34
```

当前验证机器为无刘海 Mac，因此已验证顶部浮动胶囊 fallback。真实刘海机的精确 notch frame 仍需要在带刘海设备上复验。

---

## 完成标准

- [x] App 启动后，顶部出现黑色圆角矩形
- [x] 鼠标 Hover 后面板向下展开，移开后收回
- [x] `EventBus.sessionState` 状态变化会驱动 compact / pill 形态选择
- [x] WindowLevel、collectionBehavior、透明背景和不抢焦点策略已实现
- [x] 无刘海 Mac 上不崩溃，降级为顶部浮动胶囊
- [x] 屏幕参数变化时自动重新定位
- [ ] 带刘海 Mac 上精确贴合真实刘海区域，待设备复验
- [ ] Codex 实际工作流端到端触发 compact / pill，待真实 Codex 场景复验
