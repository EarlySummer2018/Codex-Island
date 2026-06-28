# 02 — 数据采集层：JSONL 监听 + WebSocket

> 目标：Rust sidecar 能实时读取 Codex 本地状态数据，并向主 App 推送脱敏后的原始事件。

---

## 需求对齐

本阶段对应 `demand.md` 的 3.1 数据采集，但只做采集通路，不做 Token 差分和状态机。

02 负责：

- 监听 `~/.codex/sessions/` 下新增和修改的 `.jsonl`
- 启动时扫描历史 sessions 的最新 `token_count`，生成全局 token 快照
- 增量读取新增行，跳过非法 JSON，不崩溃
- 提取与阶段一相关的白名单事件
- 尝试连接 `ws://127.0.0.1:4500`，失败时静默降级
- 断连后 3 秒自动重连
- 将 JSONL 与 WebSocket 两路事件合并为 `RawEvent`
- 通过 Unix Socket 推送给未来 Swift 主进程

02 不负责：

- Token 累计值转 `TokenSnapshot`（03）
- 单轮差分和非负校验（03）
- `idle` / `thinking` / `streaming` / `awaiting_input` 状态机（04）
- Streaming 4 秒超时兜底（04）
- Swift 端接入 sidecar（09 或后续集成）

---

## 数据通道

### 通道 A：JSONL 文件监听（主路径）

```text
~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl
```

策略：

- 启动时扫描最近 24 小时内修改过的 `.jsonl`
- 将最后修改时间最新的 `.jsonl` 标记为 active session
- 已存在文件从末尾开始监听，避免重放大量历史
- 新建 `.jsonl` 从头读取，捕获会话初始化事件
- 多个会话同时写入时，切换到最后修改的文件
- 文件截断时重置 offset
- 每 500ms 轮询最近 24 小时内 JSONL 文件大小，作为 macOS FSEvents 漏报或只上报目录变更时的兜底
- 目录不存在或暂时不可读时记录 warning，不让主进程崩溃

Codex Desktop App 经常复用已存在的 rollout 文件继续追加事件；在这种情况下，`notify` 不一定稳定给出具体 JSONL 文件路径。因此 02 不能只依赖文件系统事件，必须同时保留轮询兜底，发现已知文件 size 变化后直接 tail 新增行。

### 通道 B：App-Server WebSocket（辅助路径）

```text
ws://127.0.0.1:4500
```

策略：

- 默认连接 `127.0.0.1:4500`
- 可通过 `CODEX_APP_SERVER_HOST` 和 `CODEX_APP_SERVER_PORT` 覆盖
- 连接失败只写 debug 日志，继续依赖 JSONL 主路径
- 断连后按 3 秒间隔重连

---

## 隐私边界

最新 PRD 明确阶段一不读取 AI 回复具体文字内容。因此 02 不再把 JSONL 原始整行直接推给 IPC。

JSONL 只转发白名单事件：

| 事件 | 保留字段 | 用途 |
|------|----------|------|
| `session_init` | `session_id` / `model` | 识别会话 |
| `session_meta` | `id` / `cwd` / `cli_version` | 兼容 Codex Desktop 实际格式 |
| `token_count` | `input_tokens` / `cached_input_tokens` / `output_tokens` / `reasoning_tokens` | 03 Token 解析 |
| `task_started` | 仅事件类型 | 04 进入 Thinking |
| `task_complete` | 仅事件类型 | 04 回到 Idle |
| `agent_message` | `phase` | 04 输出中状态；不保留正文 |
| `user_message` | 仅事件类型 | 04 进入 Thinking |
| `assistant_message_start` | 仅事件类型 | 04 状态辅助 |
| `assistant_message_stop` | 仅事件类型 | 04 退出 Streaming 辅助 |
| `tool_call` | `tool` / `command` | 等待原因预备字段 |
| `awaiting_approval` | `tool` / `command` | 04/08 AwaitingInput |
| `tool_approval` | `approved` | AwaitingInput 退出 |

明确丢弃：

- `assistant_message_delta.content`
- 用户消息正文
- 任何未列入白名单的 JSONL payload

真实 Codex JSONL 的 `token_count` 通常位于 `payload.info.total_token_usage`：

```json
{
  "type": "event_msg",
  "payload": {
    "type": "token_count",
    "info": {
      "total_token_usage": {
        "input_tokens": 120,
        "cached_input_tokens": 40,
        "output_tokens": 12,
        "reasoning_output_tokens": 0
      }
    }
  }
}
```

02 会把它归一化为内部平铺字段，并丢弃 `info` / `rate_limits` 等非白名单内容。

启动时会从最新活跃 JSONL 中只回放两个脱敏检查点：

- 最新的 `token_count`，用于避免 App 刚启动时统计全为 0
- 最新的状态事件，尤其是 Codex 实际写入的 `task_complete`

IPC 会缓存最近的 `GlobalTokenUsageSnapshot`、`TokenSnapshot` 和 `SessionStateEvent`。新客户端连接后会立即收到这些快照，避免 Swift 端在 sidecar 启动早于 IPC 连接时错过启动回放。

## 全局 token 聚合

宠物进化需要使用所有 Codex 会话的累计 token，而不是当前 active session。因此 watcher 启动时会扫描：

```text
~/.codex/sessions/**/*.jsonl
```

扫描策略：

- 只读取每个 session 最新的 `token_count`
- 不读取或转发用户正文、AI 回复正文
- session id 优先使用 JSONL 元数据，缺失时从 rollout 文件名 UUID 兜底
- 多个文件属于同一 session 时只保留最新 totals，不重复累加
- 运行时收到某 session 的新 `TokenSnapshot` 后，用该 session 最新 totals 覆盖旧值，再广播全局累计

IPC 消息格式：

```json
{
  "type": "global_token_usage",
  "total_input": 300,
  "total_cached_input": 140,
  "total_output": 37,
  "total_reasoning": 3,
  "total_tokens": 337,
  "session_count": 2,
  "updated_at": "2026-06-28T08:00:00Z"
}
```

## 会话识别与多会话边界

文件监听层会跟踪最近 24 小时内的多个 `rollout-*.jsonl` 文件。每条脱敏事件都会携带独立的 `session_id`，后续状态机和 Token parser 按会话分桶处理。

`session_id` 来源优先级：

1. `session_init.payload.session_id`
2. `session_meta.payload.id`
3. `rollout-...-UUID.jsonl` 文件名中的 UUID 兜底

因此新开 Codex 会话即使还没有写入元数据行，只要文件名包含 rollout UUID，也能先进入 `thinking` / `streaming` 等状态。阶段一 UI 仍然只显示一个胶囊；多会话列表或多个胶囊不属于当前阶段。

WebSocket 只转发状态 notification：

- `turn/start`
- `turn/stop`
- `tool/approval/request`

后续 04 会决定这些事件如何影响状态优先级。

---

## 当前实现文件

```text
codex-watcher/src/
├── main.rs                         # 启动 IPC、watchers、事件主循环
├── parser/mod.rs                   # RawEvent 枚举
├── parser/global_token_usage.rs    # 全局 token 聚合与历史扫描
├── watcher/
│   ├── jsonl_watcher.rs            # JSONL 递归监听、offset tail、事件脱敏
│   ├── mod.rs                      # JSONL + WebSocket 合并入口
│   └── ws_client.rs                # App-Server WebSocket 客户端
└── ipc/
    ├── mod.rs
    └── unix_socket.rs              # 一行一个 JSON 的 Unix Socket 广播
```

IPC 默认路径：

```text
/tmp/codex-island.sock
```

可通过环境变量覆盖：

```bash
CODEX_HOME=/path/to/codex-home
CODEX_ISLAND_SOCKET=/tmp/custom.sock
CODEX_APP_SERVER_HOST=127.0.0.1
CODEX_APP_SERVER_PORT=4500
```

---

## 验证方法

启动 watcher：

```bash
make run-watcher
```

统一验证：

```bash
make verify
```

当前 `make verify` 覆盖：

- Rust 单元测试
- WebSocket 本地回环测试
- macOS App Debug 构建

手动真实流验证：

```bash
# 终端 1
make run-watcher

# 终端 2
codex "用一句话介绍冒泡排序"
```

预期 watcher 日志出现：

```text
File watcher started on ...
Raw event: JsonlLine(...)
```

如果需要观察 IPC：

```bash
nc -U /tmp/codex-island.sock
```

---

## 完成标准

- [x] 能监听 Codex sessions 目录下 `.jsonl` 新增/修改
- [x] 能按最后修改时间维护 active session
- [x] 能从 offset 增量读取新增 JSONL 行
- [x] 非法 JSON 行跳过且不崩溃
- [x] JSONL 事件按 PRD 隐私边界脱敏
- [x] WebSocket 连接失败时静默降级
- [x] WebSocket 断连后自动重连
- [x] 两路事件合并为 `RawEvent`
- [x] Unix Socket IPC 能向客户端推送 JSON 行
- [x] 启动时广播全局 token 快照
- [x] IPC replay 同时包含 global token、当前 token、当前状态
- [x] 单元测试和 `make verify` 通过

---

## 常见问题

**Q: WebSocket 连接被拒绝怎么办？**
A: 这是允许的降级路径。只要 JSONL 监听可用，阶段一仍可继续工作。需要调试 WebSocket 时可先启动 Codex App-Server：`codex app-server --listen ws://127.0.0.1:4500`。

**Q: 为什么不转发完整 JSONL 行？**
A: PRD 要求阶段一不读取 AI 回复具体文字内容，因此 02 只转发 token 与状态相关字段。

**Q: 找不到 `.jsonl` 文件怎么办？**
A: 先用 Codex 跑一次简单对话，等待 sessions 文件生成。
