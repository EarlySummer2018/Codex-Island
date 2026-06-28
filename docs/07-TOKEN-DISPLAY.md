# 07 — Token 实时数字展示 UI

> 目标：在 Pill 与 Expanded 形态中展示当前会话 token 数据，提供数字滚动动画、颜色分区和历史趋势图。

---

## 实现状态

✅ 已实现并通过本地验证。

当前范围只包含 Token 展示 UI：

- 常驻 Pill 形态展示 `IN` / `CACHE(%)` / `OUT` / `TOTAL`
- Pill 宽度为 440pt，为四组 token 和巡游宠物预留空间
- Token 数字仍显示当前 active session，不显示全局累计
- 宠物进化使用全局累计 token，由 06 的 `PetEvolutionStore` 驱动
- Hover Expanded 展示宠物、状态、四格 Token 卡片
- 会话历史超过 1 条时展示最近 20 条 output delta 折线图
- 数字使用等宽字体，变化时使用 numeric transition 与 0.3 秒白色高亮
- Hover 展开只做尺寸与 opacity 动画，避免直角闪烁和额外浅黑背景层

---

## 文件结构

```
CodexIsland/
├── UI/
│   ├── Components/
│   │   ├── AnimatedTokenCounter.swift
│   │   ├── TokenCard.swift
│   │   ├── TokenColors.swift
│   │   ├── TokenHistoryChart.swift
│   │   ├── TokenInfoRow.swift
│   │   ├── RoamingPetView.swift
│   │   └── TokenPill.swift
│   ├── States/
│   │   ├── ExpandedPanelView.swift
│   │   ├── IdleView.swift
│   │   ├── StreamingView.swift
│   │   └── ThinkingView.swift
│   └── NotchWindow/
│       └── NotchIslandView.swift
└── Core/
    ├── TokenFormatter.swift
    └── TokenStore.swift
```

---

## Pill 形态

[StreamingView.swift](/Applications/APP/Codex-Island/CodexIsland/UI/States/StreamingView.swift) 负责 Pill 中的 Token 行：

```
[宠物巡游区] IN 1.2K [空隙] CACHE 800 66.7% [空隙] OUT 342 [空隙] TOTAL 1.5K [边缘]
```

[TokenInfoRow.swift](/Applications/APP/Codex-Island/CodexIsland/UI/Components/TokenInfoRow.swift) 展示四组数据：

| 字段 | 来源 | 颜色 |
|------|------|------|
| `IN` | `TokenStore.totalInput` | `#60A5FA` |
| `CACHE` | `TokenStore.totalCachedInput` + `cacheHitPercent` | `#34D399` |
| `OUT` | `TokenStore.totalOutput` | `#FB923C` |
| `TOTAL` | `TokenStore.totalTokens` | `#E5E7EB` |

`TokenInfoRow` 在 token 组之间插入透明 `petSlot`，`RoamingPetView` 只在这些安全锚点和左右边缘移动，避免遮挡数字。

---

## 常驻状态

Pill 不再按 `idle` / `thinking` / `streaming` 切换成不同布局；常驻展示同一组 token 数字，宠物动画根据状态切换：

| 状态 | 宠物动画 |
|------|----------|
| `idle` | `idle_breathe` |
| `thinking` | `think_sweat` |
| `streaming` | `talk_walk` |
| `awaiting_input` | `await_jump` |
| `error` | `error_fall` |

`awaiting_input` 的强提醒、通知和唤起 Codex 仍由 08 的等待模块负责。

---

## Expanded 面板

[ExpandedPanelView.swift](/Applications/APP/Codex-Island/CodexIsland/UI/States/ExpandedPanelView.swift) 已接入 Hover 展开态：

- 顶部：宠物 + 当前状态 + 总 token 摘要
- 四格卡片：Input / Cached / Uncached / Output
- 历史折线图：`TokenStore.history.count > 1` 时显示最近 20 条 `deltaOutput`
- Header 不再使用整块半透明矩形背景，展开内容复用外层统一圆角裁剪

[TokenHistoryChart.swift](/Applications/APP/Codex-Island/CodexIsland/UI/Components/TokenHistoryChart.swift) 使用 Swift Charts，不引入第三方依赖。

---

## 数字动画

[AnimatedTokenCounter.swift](/Applications/APP/Codex-Island/CodexIsland/UI/Components/AnimatedTokenCounter.swift) 实现：

- `contentTransition(.numericText(countsDown: false))`
- `spring(response: 0.4, dampingFraction: 0.8)`
- 数值变化时白色高亮 0.3 秒，再恢复字段颜色
- `.monospacedDigit()` 避免数字变化造成布局跳动

为了兼容 macOS 13 target，`numericText` transition 包在 `#available(macOS 14.0, *)` 中；低版本使用上滑淡入/淡出转场作为滚动 fallback，并保留数值更新和高亮。

---

## 格式化规则

格式化沿用 [TokenFormatter.swift](/Applications/APP/Codex-Island/CodexIsland/Core/TokenFormatter.swift)：

| 范围 | 格式 | 示例 |
|------|------|------|
| `0..<1_000` | 原始整数 | `342` |
| `1_000..<10_000` | 一位小数 + K | `1.2K` |
| `10_000..<1_000_000` | 整数 + K | `12K` |
| `>=1_000_000` | 一位小数 + M | `1.2M` |

---

## 验证结果

已执行：

```bash
xcodegen generate
(cd codex-watcher && cargo test)
python3 scripts/ipc_smoke_test.py codex-watcher/target/debug/codex-watcher
make build-macos
python3 scripts/app_runtime_smoke_test.py
```

结果：

- Rust `cargo test`：39 passed
- IPC smoke test：通过，含全局 token replay
- macOS Debug build：`BUILD SUCCEEDED`
- App runtime smoke：窗口 `440x34`，顶部 `Y=18`
- Swift Charts 编译通过
- 新增 Token UI 文件已加入 Xcode 工程

---

## 剩余依赖

- 需要用真实 Codex 长会话验证 UI 端的实时递增延迟、巡游遮挡情况和 hover 展开视觉
- AwaitingInput 的强提醒、通知和唤起 Codex 能力已由 08 补齐
