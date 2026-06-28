# 04 — 会话状态机

> 目标：综合脱敏 JSONL 事件和 WebSocket 状态消息，判断 Codex 当前状态，并向主 App 推送 `SessionStateEvent`。

---

## 需求对齐

本阶段对应 `demand.md` 的 3.2 会话状态机和 3.1.3 Streaming 超时兜底。

04 负责：

- 实现 `idle` / `thinking` / `streaming` / `awaiting_input` / `error`
- 从 02 的脱敏 JSONL 事件推断状态变化
- 从 WebSocket `turn/start`、`turn/stop`、`tool/approval/request` 处理实时状态
- `awaiting_input` 携带 `AwaitReason`
- `streaming` 连续 4 秒无 output token 增长后自动回 `idle`
- `error` 3 秒后自动回 `idle`
- Swift 端提供状态模型和 `EventBus`

04 不负责：

- 灵动岛窗口和动画（05）
- 像素宠物渲染（06）
- Token 数字 UI（07）
- 等待状态视觉提示、系统通知、一键唤起 Codex（08）
- Swift 端 IPC 连接实现（09 或后续集成）

---

## 状态定义

| 状态 | 含义 | 进入条件 | 退出条件 |
|------|------|----------|----------|
| `idle` | 无活跃会话，或会话已完成 | 初始状态；`assistant_message_stop`；`turn/stop`；超时兜底 | `user_message` / `turn/start` |
| `thinking` | 用户已提问，等待第一个 output token | `user_message`；`turn/start`；工具审批通过 | output token 增加；等待用户输入 |
| `streaming` | AI 正在输出，`output_tokens` 增加 | `token_count.output_tokens` 增加 | `assistant_message_stop`；`turn/stop`；4 秒无 output 增长 |
| `awaiting_input` | Codex 请求用户确认 | `awaiting_approval`；`tool/approval/request` | `tool_approval.approved=true` → `thinking`；拒绝/取消 → `idle` |
| `error` | 会话出错 | `error` / `turn_error` / `stream_error`，或 `StateParser::set_error` | 3 秒后自动回 `idle` |

`awaiting_input` 优先级最高。处于等待状态时，新的 `token_count` 不会把状态切到 `streaming`。

---

## 当前实现文件

```text
codex-watcher/src/parser/
├── mod.rs
├── token_parser.rs
└── state_parser.rs

CodexIsland/Core/
├── EventBus.swift
├── SessionState.swift
├── TokenFormatter.swift
└── TokenStore.swift
```

Rust `main.rs` 当前会：

- 接收 `RawEvent`
- 交给 `StateParser::process_event`
- 交给 `TokenParser::process_event`
- 将 `SessionStateEvent` 通过 Unix Socket IPC 广播
- 每秒调用 `StateParser::check_timeouts`

---

## Rust 数据模型

`SessionState`：

```rust
#[serde(rename_all = "snake_case")]
pub enum SessionState {
    Idle,
    Thinking,
    Streaming,
    AwaitingInput,
    Error,
}
```

`AwaitReason`：

```rust
#[serde(tag = "type", rename_all = "snake_case")]
pub enum AwaitReason {
    ToolApproval { tool: String, command: Option<String> },
    Question { text: Option<String> },
}
```

`SessionStateEvent`：

```rust
pub struct SessionStateEvent {
    pub session_id: String,
    pub state: SessionState,
    pub timestamp: DateTime<Utc>,
    pub await_reason: Option<AwaitReason>,
}
```

---

## 事件规则

JSONL 脱敏事件：

| JSONL payload type | 状态动作 |
|--------------------|----------|
| `user_message` | `thinking` |
| `assistant_message_start` | 保持当前状态 |
| `token_count` 且 `output_tokens` 增加 | `streaming` |
| `assistant_message_stop` | `idle` |
| `awaiting_approval` | `awaiting_input`，附带工具名和命令 |
| `tool_approval.approved=true` | `thinking` |
| `tool_approval.approved=false` | `idle` |
| `error` / `turn_error` / `stream_error` | `error` |

WebSocket notification：

| method | 状态动作 |
|--------|----------|
| `turn/start` | `thinking` |
| `turn/stop` | `idle` |
| `tool/approval/request` | `awaiting_input`，附带工具名和命令 |

注意：02 按 PRD 隐私要求丢弃 `assistant_message_delta.content`，因此 04 不依赖文本 delta 判断输出中状态，只依赖 `token_count.output_tokens` 增长。

---

## Swift 数据模型

`SessionState.swift` 提供：

- `CodexSessionState`
- `AwaitReason`
- `SessionStateEvent`

`EventBus.swift` 提供：

- `sessionState`
- `awaitReason`
- `latestToken`
- `activeSessionId`
- `handleStateEvent(_:)`
- `handleTokenSnapshot(_:)`

这些都是数据层模型，不包含 UI、通知、窗口或宠物逻辑。

## 多会话显示策略

Rust 状态机和 Token parser 都按 `session_id` 分桶，Swift `EventBus` 也会保存每个会话的状态、等待原因、Token 快照和最后活动时间。

阶段一仍然只有一个灵动岛胶囊。`EventBus` 会从多个会话中选一个投影到现有 UI：

1. `awaiting_input`
2. `streaming`
3. `thinking`
4. `error`
5. `idle`

同优先级时选择最后活动时间最新的会话。`TokenStore` 同样按会话保存历史，胶囊切换 active session 时只显示该会话的 token 统计。多会话并列列表、多个胶囊和手动切换会话属于后续功能。

为了避免短会话 `thinking` / `streaming` / `idle` 切换过快导致肉眼看不到，Swift `EventBus` 会把 active session 的 `idle` 收尾延迟到活跃状态至少显示 1.4 秒后再应用。新的活跃会话事件仍会立即抢占显示。

---

## 当前实现状态

- [x] Rust `StateParser` 已实现
- [x] `SessionStateEvent` 支持 `serde`
- [x] JSONL 状态推断已实现
- [x] WebSocket 状态事件已实现
- [x] `awaiting_input` 工具审批原因已实现
- [x] Streaming 4 秒超时回 Idle 已实现
- [x] Error 3 秒回 Idle 已实现
- [x] `main.rs` 已接入状态机和 timeout interval
- [x] Unix Socket IPC 已能广播 `SessionStateEvent`
- [x] Swift `SessionState.swift` 已新增
- [x] Swift `EventBus.swift` 已新增
- [x] 单元测试已覆盖核心状态转换和超时规则
- [x] `cargo test state_parser` 已通过
- [x] `make verify` 已通过，包含 Rust 全量测试和 Xcode Debug 构建

---

## 验证命令

```bash
cd codex-watcher
cargo test state_parser
```

统一验证：

```bash
make verify
```

本机验证记录：

```text
cargo test state_parser: 8 passed
cargo test: 22 passed
xcodebuild Debug build: BUILD SUCCEEDED
make verify: passed
make test-app-runtime: passed
```

---

## 完成标准

- [x] 新开 Codex 对话时，状态机切换到 `thinking`
- [x] AI 开始输出时，切换到 `streaming`
- [x] AI 输出完成后，切换回 `idle`
- [x] Codex 请求工具审批时，切换到 `awaiting_input`，`await_reason` 包含正确 tool 名称
- [x] 用户审批后，切换到 `thinking`
- [x] 用户拒绝/取消审批后，切换到 `idle`
- [x] 4 秒无 output 增长后，从 `streaming` 自动回 `idle`
- [x] `error` 3 秒后自动回 `idle`
