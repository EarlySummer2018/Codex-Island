# 08 — "等待回复"状态 UI

> 目标：当 Codex 需要用户确认或回答时，用醒目的视觉、通知和快捷入口提醒用户。

---

## 实现状态

✅ 已实现并通过本地验证。

当前范围只包含 AwaitingInput 体验层：

- Pill 形态显示红色「等待您的回复」
- 宠物切换为 `await_jump`，沿用 06 的红色脉冲光圈
- Pill 外边框红色呼吸闪烁
- 显示等待原因：工具审批 / 问题文本
- 提供「回复」按钮，点击后激活运行中的 Codex；未运行时尝试 `open -a Codex`
- 启动时申请系统通知权限，并注册 `CODEX_AWAIT` 通知类别
- 进入 Awaiting UI 时发送系统通知，30 秒内同一会话不重复发送
- Hover Expanded 时在 Token 卡片上方显示等待详情和「前往 Codex 回复」按钮

09 已接入真实 IPC 链路：

- Rust sidecar 会将 `awaiting_input` 状态事件推送到 Swift `EventBus`
- Swift UI 可随 IPC 状态切换到等待视图
- IPC smoke test 已覆盖 `awaiting_input` 消息
- 真实 Codex 工具审批场景仍需手动复验通知、防刷屏和唤起链路

---

## 文件结构

```
CodexIsland/
├── Core/
│   ├── AwaitNotificationCoordinator.swift
│   └── CodexActivation.swift
├── App/
│   └── AppDelegate.swift
└── UI/
    ├── Components/
    │   ├── ActivateCodexButton.swift
    │   └── AwaitReasonLabel.swift
    ├── States/
    │   ├── AwaitingDetailPanel.swift
    │   ├── AwaitingView.swift
    │   └── ExpandedPanelView.swift
    └── NotchWindow/
        └── NotchIslandView.swift
```

---

## Pill 等待视图

[AwaitingView.swift](/Applications/APP/Codex-Island/CodexIsland/UI/States/AwaitingView.swift) 已接入 `NotchIslandView` 的 `.awaitingInput` 分支：

```
[跳脚宠物] | 等待您的回复
           | shell: command preview...
                                      [回复]
```

实现细节：

- `PixelPetView(animationName: .awaitJump)` 显示焦虑跳脚动画
- `PixelPetView` 内部自动叠加 `PulseRingView`
- 外层 `RoundedRectangle` 使用红色 `stroke`，`1.2s` 呼吸动画
- `AwaitReasonLabel` 显示工具名/命令预览或问题文本
- `ActivateCodexButton(title: "回复")` 负责唤起 Codex

等待状态不再使用 07 的通用 `StreamingView`，避免弱化提醒。

---

## 等待原因展示

[AwaitReasonLabel.swift](/Applications/APP/Codex-Island/CodexIsland/UI/Components/AwaitReasonLabel.swift) 支持：

| 类型 | 展示规则 |
|------|----------|
| `toolApproval(tool, command)` | `{tool}: {command 前 30 字符}` |
| `question(text)` | `{question 前 40 字符}` |
| `nil` | `需要您的输入` |

工具审批使用 `terminal.fill` 图标和橙色强调；问题使用 `questionmark.circle.fill` 图标和蓝色强调。

---

## 唤起 Codex

[CodexActivation.swift](/Applications/APP/Codex-Island/CodexIsland/Core/CodexActivation.swift) 提供统一入口：

1. 在 `NSWorkspace.shared.runningApplications` 中查找 bundle id 或应用名包含 `codex` 的进程
2. 找到后调用 `activate(options: .activateIgnoringOtherApps)`
3. 未找到时使用 `/usr/bin/open -a Codex` 尝试启动

[ActivateCodexButton.swift](/Applications/APP/Codex-Island/CodexIsland/UI/Components/ActivateCodexButton.swift) 提供两种样式：

- Pill 小按钮：`回复`
- Expanded 全宽按钮：`前往 Codex 回复`

---

## Expanded 等待详情

[AwaitingDetailPanel.swift](/Applications/APP/Codex-Island/CodexIsland/UI/States/AwaitingDetailPanel.swift) 在 `ExpandedPanelView` 中仅等待状态显示，位置在 Token 四格卡片上方。

展示内容：

- 红色警示图标 + `Codex 需要您的确认`
- 工具审批：工具名称 + 命令内容，命令最多 4 行
- 问题文本：最多 3 行
- 全宽红色按钮：`前往 Codex 回复`

---

## 系统通知

[AwaitNotificationCoordinator.swift](/Applications/APP/Codex-Island/CodexIsland/Core/AwaitNotificationCoordinator.swift) 负责通知：

- `configure()` 在 App 启动时调用
- 注册通知类别：`CODEX_AWAIT`
- 请求权限：`.alert` / `.sound` / `.badge`
- `notifyIfNeeded(sessionId:reason:)` 根据会话做 30 秒冷却
- 通知标题：`Codex 正在等待您的回复`
- 通知正文包含工具审批或问题文本的预览

[AppDelegate.swift](/Applications/APP/Codex-Island/CodexIsland/App/AppDelegate.swift) 已在启动时调用：

```swift
AwaitNotificationCoordinator.shared.configure()
```

如果用户拒绝通知权限，App 只保留视觉提醒，不崩溃。

---

## 验证结果

已执行：

```bash
xcodegen generate
make verify
```

结果：

- Rust `cargo test`：20 passed
- macOS Debug build：`BUILD SUCCEEDED`
- 新增 `UserNotifications` 依赖编译通过
- 新增 Awaiting UI 文件已加入 Xcode 工程

---

## 剩余依赖

- 需要用真实 Codex `awaiting_input` 场景验证通知触发、防刷屏和按钮唤起链路
- 需要用真实 Codex 审批/取消场景验证 Swift UI 能跟随状态机切回 Thinking 或 Idle
