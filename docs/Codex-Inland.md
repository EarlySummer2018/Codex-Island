# Codex Island — 项目总索引

> macOS 灵动岛 × Codex 状态监听 × 像素宠物伴侣

---

## PRD 对齐

当前以 `demand.md` v1.0 为准：

- 阶段一：核心监听 + 灵动岛 UI
- 阶段二：智能记忆系统，当前不实现
- 阶段一遵守最小权限：只读 Codex sessions，不写 Codex 文件
- WebSocket 是辅助路径，不可用时必须静默降级到 JSONL
- 01/02/03/04/05/06/07/08/09 已完成工程初始化、脱敏数据采集、Token 解析、状态机、Notch 窗口、像素宠物、Token UI、等待提醒 UI 和阶段一集成链路
- 阶段一代码链路已打通；进入阶段二前仍需做真实 Codex 长会话、工具审批、刘海真机和性能复验

## 开发阶段

### 阶段一：核心监听 + 灵动岛 UI（当前优先）

| 文档 | 内容 | 状态 |
|------|------|------|
| [01-SETUP.md](./01-SETUP.md) | 工程初始化、目录结构、依赖配置 | ✅ 实现完成（已验证） |
| [02-DATA-WATCHER.md](./02-DATA-WATCHER.md) | Codex JSONL 文件监听 + App-Server WebSocket | ✅ 实现完成（已验证） |
| [03-TOKEN-PARSER.md](./03-TOKEN-PARSER.md) | Token 数据解析：总量/缓存/输入/输出 | ✅ 实现完成（已验证） |
| [04-STATE-MACHINE.md](./04-STATE-MACHINE.md) | 会话状态机：Idle/Thinking/Streaming/AwaitingInput | ✅ 实现完成（已验证） |
| [05-NOTCH-WINDOW.md](./05-NOTCH-WINDOW.md) | macOS 刘海窗口：NSPanel 创建与定位 | ✅ 实现完成（已验证，刘海真机待复验） |
| [06-PIXEL-PET.md](./06-PIXEL-PET.md) | 像素宠物：动画帧、状态驱动、SwiftUI 渲染 | ✅ 实现完成（已验证，正式素材待补） |
| [07-TOKEN-DISPLAY.md](./07-TOKEN-DISPLAY.md) | Token 实时数字展示 UI：滚动动画、颜色分区 | ✅ 实现完成（IPC 已接入，真实 Codex 长会话待复验） |
| [08-AWAITING-UI.md](./08-AWAITING-UI.md) | "等待回复"状态 UI：宠物动画 + 脉冲指示 + 通知 + 唤起 Codex | ✅ 实现完成（IPC 已接入，真实 Codex 审批场景待复验） |
| [09-INTEGRATION.md](./09-INTEGRATION.md) | 阶段一集成测试与 Debug 指南 | ✅ 实现完成（已验证） |

### 阶段二：记忆系统（阶段一完成后开始）

| 文档 | 内容 | 状态 |
|------|------|------|
| [10-MEMORY-ARCH.md](./10-MEMORY-ARCH.md) | 三层记忆架构总体设计 | 待开始 |
| [11-MEMORY-EXTRACT.md](./11-MEMORY-EXTRACT.md) | 提取流水线：LLM 结构化抽取 | 待开始 |
| [12-MEMORY-STORE.md](./12-MEMORY-STORE.md) | 存储层：SQLite-VSS + FTS5 + 知识图谱 | 待开始 |
| [13-MEMORY-RETRIEVAL.md](./13-MEMORY-RETRIEVAL.md) | 检索层：向量 + BM25 + 图遍历 + RRF 融合 | 待开始 |
| [14-MEMORY-INJECT.md](./14-MEMORY-INJECT.md) | 注入出口：AGENTS.md / MCP / Hook | 待开始 |
| [15-MEMORY-UI.md](./15-MEMORY-UI.md) | 记忆可视化面板（灵动岛展开态） | 待开始 |

---

## 技术栈快速参考

```
语言        Swift 5.9 + Rust 1.78
UI          SwiftUI + AppKit (NSPanel)
宠物渲染    SwiftUI Canvas（正式 PNG 帧可替换）
数据监听    Rust: notify + tokio-tungstenite
IPC         Unix Domain Socket (JSONL 帧)
构建        XcodeGen + Xcode 15 + cargo
最低系统    macOS Ventura 13.0
测试设备    带刘海 Mac 优先；无刘海 Mac 需验证顶部浮动胶囊降级
```

## 关键路径依赖

```
Codex CLI v0.100+ 已安装  ←  JSONL sessions 目录存在
Codex Desktop 已安装      ←  App-Server WebSocket 可用时增强实时状态
macOS 13+ (Ventura)       ←  NSScreen.auxiliaryTopLeftArea API
Xcode 15+                 ←  Swift 5.9 语言特性
Rust 1.78+                ←  notify crate async 特性
```

## 显示数据链路

阶段一的显示链路是：

```text
~/.codex/sessions/**/*.jsonl
  → codex-watcher 脱敏、补 session_id、解析状态和 Token
  → Unix Socket IPC
  → SidecarBridge 解码
  → EventBus 按 session_id 分桶并选出 active session
  → TokenStore / NotchIslandView 显示单个胶囊
```

Codex 可以多个会话同时运行，数据层按会话独立记录。当前 UI 仍是单胶囊策略：显示优先级最高且最近活动的会话；多胶囊或会话切换面板留到后续阶段。

## 当前已实现结构（01/02/03/04/05/06/07/08/09）

```
CodexIsland/
├── CodexIsland.xcodeproj           # 由 project.yml 生成
├── CodexIsland/                    # Swift 空壳 App
│   ├── App/
│   │   ├── AppDelegate.swift
│   │   └── main.swift
│   ├── Core/
│   │   ├── AwaitNotificationCoordinator.swift
│   │   ├── CodexActivation.swift
│   │   ├── EventBus.swift
│   │   ├── SessionState.swift
│   │   ├── TokenFormatter.swift
│   │   └── TokenStore.swift
│   ├── DataLayer/
│   │   └── SidecarBridge.swift     # Rust sidecar 生命周期、IPC 连接与事件解码
│   ├── Assets.xcassets/
│   │   └── PixelPet/               # 正式 PNG 帧素材目录，当前使用占位绘制
│   ├── UI/
│   │   ├── Components/
│   │   │   ├── ActivateCodexButton.swift
│   │   │   ├── AnimatedTokenCounter.swift
│   │   │   ├── AwaitReasonLabel.swift
│   │   │   ├── PetAnimation.swift
│   │   │   ├── PixelPetView.swift
│   │   │   ├── PlaceholderPetView.swift
│   │   │   ├── PulseRingView.swift
│   │   │   ├── TokenCard.swift
│   │   │   ├── TokenColors.swift
│   │   │   ├── TokenHistoryChart.swift
│   │   │   ├── TokenInfoRow.swift
│   │   │   └── TokenPill.swift
│   │   ├── States/
│   │   │   ├── AwaitingDetailPanel.swift
│   │   │   ├── AwaitingView.swift
│   │   │   ├── ExpandedPanelView.swift
│   │   │   ├── IdleView.swift
│   │   │   ├── StreamingView.swift
│   │   │   └── ThinkingView.swift
│   │   └── NotchWindow/
│   │       ├── IslandShape.swift
│   │       ├── NotchIslandPanel.swift
│   │       └── NotchIslandView.swift
│   ├── CodexIsland.entitlements    # 当前为空，保持最小权限
│   └── Info.plist
├── codex-watcher/
│   ├── Cargo.toml
│   └── src/
│       ├── main.rs
│       ├── parser/
│       │   ├── mod.rs              # RawEvent
│       │   ├── state_parser.rs     # 会话状态机
│       │   └── token_parser.rs     # TokenSnapshot 差分解析
│       ├── watcher/
│       │   ├── jsonl_watcher.rs    # JSONL 监听 + 脱敏
│       │   └── ws_client.rs        # WebSocket 客户端
│       └── ipc/unix_socket.rs      # Unix Socket 推送
├── scripts/
│   ├── app_runtime_smoke_test.py   # 启动 Debug App 的端到端运行验证
│   └── ipc_smoke_test.py           # 临时 CODEX_HOME 的 IPC 冒烟测试
├── docs/
├── Makefile
└── project.yml                     # Xcode post-build 编译并拷贝 sidecar
```

## 阶段一目标结构（逐步补齐）

```
CodexIsland/
├── CodexIsland.xcodeproj
├── CodexIsland/                    # Swift 主 App
│   ├── App/
│   │   ├── AppDelegate.swift
│   │   └── main.swift
│   ├── Core/
│   │   ├── EventBus.swift          # Combine 事件总线
│   │   ├── SessionState.swift      # 状态机
│   │   └── TokenStore.swift        # Token 累计存储
│   ├── DataLayer/
│   │   ├── SidecarBridge.swift     # Rust sidecar IPC
│   │   └── SessionEvent.swift      # 事件模型
│   ├── UI/
│   │   ├── NotchWindow/
│   │   │   ├── IslandShape.swift
│   │   │   ├── NotchIslandPanel.swift
│   │   │   └── NotchIslandView.swift
│   │   ├── States/
│   │   │   ├── IdleView.swift
│   │   │   ├── ThinkingView.swift
│   │   │   ├── StreamingView.swift
│   │   │   └── AwaitingView.swift
│   │   └── Components/
│   │       ├── PixelPetView.swift
│   │       ├── TokenCounterView.swift
│   │       └── PulseIndicator.swift
│   └── Assets.xcassets/
│       └── PixelPet/               # 宠物像素帧
│
├── codex-watcher/                  # Rust sidecar
│   ├── Cargo.toml
│   └── src/
│       ├── main.rs
│       ├── watcher/
│       │   ├── jsonl_watcher.rs    # 文件监听
│       │   └── ws_client.rs        # WebSocket 客户端
│       ├── parser/
│       │   ├── token_parser.rs     # token_count 解析
│       │   └── state_parser.rs     # 状态推断
│       └── ipc/
│           └── unix_socket.rs      # Unix Socket 服务端
│
└── docs/                           # 本目录
```

---

## 开发约定

- 若项目后续初始化 Git，建议每个文档对应一个独立分支：`feat/02-data-watcher` 等
- 每完成一个文档的任务，在此文件更新状态为 `✅ 完成`
- 遇到 Codex JSONL 格式变化时，优先更新 `03-TOKEN-PARSER.md`
- 像素宠物素材放在 `Assets.xcassets/PixelPet/` 下，命名规范见 `06-PIXEL-PET.md`
