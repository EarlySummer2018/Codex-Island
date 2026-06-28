# 03 — Token 数据解析

> 目标：将原始 JSONL 行解析为结构化的 TokenSnapshot，正确计算增量值

---

## 需求对齐

本阶段对应 `demand.md` 的 Token 数据字段与精度要求。

03 负责：

- 从 02 的脱敏 `token_count` 事件解析累计 Token 值
- 生成结构化 `TokenSnapshot`
- 计算单次增量，保证增量永不为负
- 计算未缓存输入与缓存命中率
- 在 sidecar 日志中输出 `TokenSnapshot`
- 提供 Swift 端 `TokenSnapshot` / `TokenStore` / `TokenFormatter` 数据模型

03 不负责：

- 会话状态机与 Streaming 超时（04）
- 灵动岛 UI 展示与数字动画（07）
- Swift 端 IPC 接入与事件总线（09 或后续集成）

---

## 核心数据模型

Codex 的 `token_count` 事件是**累计值**，需要做差分才能得到每轮的消耗。

02 会把真实 Codex 的 `payload.info.total_token_usage.*` 归一化为内部平铺字段：

- `input_tokens`
- `cached_input_tokens`
- `output_tokens`
- `reasoning_tokens`，来源于真实字段 `reasoning_output_tokens`

03 也会兼容直接传入的真实嵌套格式，避免未经过 02 脱敏路径的测试或调试数据被解析成 0。

02 启动时会回放最新的脱敏 `token_count` 检查点，因此 App 刚启动后也应能看到最近一次累计统计，而不是等待下一次 Codex 输出后才从 0 更新。

```
第 1 次 token_count：input=1200, cached=800, output=50
第 2 次 token_count：input=2800, cached=1600, output=320

本轮实际消耗：
  input_delta    = 2800 - 1200 = 1600
  cached_delta   = 1600 - 800  = 800
  uncached_delta = input_delta - cached_delta = 800  （实际发送给模型的）
  output_delta   = 320 - 50 = 270
```

---

## Rust 数据结构

当前实现文件：

```text
codex-watcher/src/parser/
├── mod.rs              # RawEvent
└── token_parser.rs     # TokenSnapshot + TokenParser
```

关键接口：

```rust
pub mod token_parser;

#[derive(Debug, Clone, Serialize)]
#[serde(tag = "source", rename_all = "snake_case")]
pub enum RawEvent {
    JsonlLine(RawJsonlLine),
    WsMessage(WsStateEvent),
}

pub struct TokenParser { /* per-session accumulator state */ }

impl TokenParser {
    pub fn process_event(&mut self, event: &RawEvent) -> Option<TokenSnapshot>;
    pub fn process_line(&mut self, line: &RawJsonlLine) -> Option<TokenSnapshot>;
    pub fn process_parsed(
        &mut self,
        session_file: &Path,
        session_id: Option<&str>,
        parsed: &Value,
    ) -> Option<TokenSnapshot>;
    pub fn clear_session(&mut self, session_file: &str);
}
```

`TokenSnapshot` 同时保留本轮增量和当前会话累计值：

```rust
pub struct TokenSnapshot {
    pub session_id: String,
    pub session_file: String,
    pub delta_input: u64,
    pub delta_cached_input: u64,
    pub delta_uncached_input: u64,
    pub delta_output: u64,
    pub delta_reasoning: u64,
    pub total_input: u64,
    pub total_cached_input: u64,
    pub total_uncached_input: u64,
    pub total_output: u64,
    pub total_reasoning: u64,
    pub cache_hit_rate: f64,
    pub timestamp: DateTime<Utc>,
    pub turn_index: u32,
}
```

---

## Swift 端数据模型（与 Rust 对应）

`CodexIsland/Core/TokenStore.swift`：

```swift
import Foundation
import Combine

/// 对应 Rust TokenSnapshot 的 Swift 模型
struct TokenSnapshot: Codable, Identifiable {
    let id = UUID()

    let sessionId: String
    let sessionFile: String

    // 本轮增量
    let deltaInput: Int
    let deltaCachedInput: Int
    let deltaUncachedInput: Int
    let deltaOutput: Int
    let deltaReasoning: Int

    // 会话累计
    let totalInput: Int
    let totalCachedInput: Int
    let totalUncachedInput: Int
    let totalOutput: Int
    let totalReasoning: Int

    let cacheHitRate: Double
    let timestamp: Date
    let turnIndex: Int

    // 计算属性
    var cacheHitPercent: String {
        String(format: "%.1f%%", cacheHitRate * 100)
    }

    var totalCost: Int {
        totalInput + totalOutput
    }

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case sessionFile = "session_file"
        case deltaInput = "delta_input"
        case deltaCachedInput = "delta_cached_input"
        case deltaUncachedInput = "delta_uncached_input"
        case deltaOutput = "delta_output"
        case deltaReasoning = "delta_reasoning"
        case totalInput = "total_input"
        case totalCachedInput = "total_cached_input"
        case totalUncachedInput = "total_uncached_input"
        case totalOutput = "total_output"
        case totalReasoning = "total_reasoning"
        case cacheHitRate = "cache_hit_rate"
        case timestamp
        case turnIndex = "turn_index"
    }
}

/// 管理当前会话的 Token 数据，作为 UI 的数据源
@MainActor
final class TokenStore: ObservableObject {
    static let shared = TokenStore()

    @Published private(set) var latest: TokenSnapshot?
    @Published private(set) var history: [TokenSnapshot] = []

    // 便捷访问属性（供 UI 直接绑定）
    var totalInput: Int { latest?.totalInput ?? 0 }
    var totalCachedInput: Int { latest?.totalCachedInput ?? 0 }
    var totalUncachedInput: Int { latest?.totalUncachedInput ?? 0 }
    var totalOutput: Int { latest?.totalOutput ?? 0 }
    var totalAllTokens: Int { totalInput + totalOutput }
    var cacheHitPercent: String { latest?.cacheHitPercent ?? "0.0%" }

    func update(with snapshot: TokenSnapshot) {
        latest = snapshot
        history.append(snapshot)
        // 只保留最近 100 条记录
        if history.count > 100 {
            history.removeFirst(history.count - 100)
        }
    }

    func reset() {
        latest = nil
        history.removeAll()
    }
}
```

---

## 数字格式化工具

`CodexIsland/Core/TokenFormatter.swift`：

```swift
import Foundation

enum TokenFormatter {
    /// 将 token 数格式化为易读字符串
    /// 1234 → "1.2K"
    /// 12345 → "12K"
    /// 1234567 → "1.2M"
    static func format(_ count: Int) -> String {
        switch count {
        case 0..<1_000:
            return "\(count)"
        case 1_000..<10_000:
            let k = Double(count) / 1_000
            return String(format: "%.1fK", k)
        case 10_000..<1_000_000:
            let k = count / 1_000
            return "\(k)K"
        default:
            let m = Double(count) / 1_000_000
            return String(format: "%.1fM", m)
        }
    }

    /// 格式化增量，带 + 号
    static func formatDelta(_ count: Int) -> String {
        guard count > 0 else { return "0" }
        return "+\(format(count))"
    }

    /// 格式化缓存节省比例
    static func formatSaving(cached: Int, total: Int) -> String {
        guard total > 0 else { return "0%" }
        let rate = Double(cached) / Double(total) * 100
        return String(format: "%.0f%%", rate)
    }
}
```

---

## 单元测试

测试位于 `codex-watcher/src/parser/token_parser.rs` 的 `#[cfg(test)]` 模块中。

当前覆盖：

- 首个 `token_count` 事件以累计值作为本次 delta
- 连续 `token_count` 事件正确计算差分
- 缓存命中率基于累计输入计算
- 非 `token_count` 事件返回 `None`
- 计数回退时 delta 使用 `saturating_sub`，永不为负
- `clear_session` 会重置差分基准和轮次

```bash
# 运行测试
cd codex-watcher
cargo test token_parser
```

---

## 当前实现状态

- [x] Rust `TokenParser` 已实现
- [x] Rust `TokenSnapshot` 已实现并支持 `serde`
- [x] `main.rs` 已接入 token parser，收到 `token_count` 时输出 `TokenSnapshot`
- [x] Swift `TokenStore.swift` 已新增
- [x] Swift `TokenFormatter.swift` 已新增
- [x] 单元测试已覆盖差分、缓存命中率、非 token 事件、计数回退、清理基准
- [ ] 当前机器需要先同意 Xcode license，之后才能运行 `cargo test` / `xcodebuild` 完整验证

---

## 完成标准

- [ ] `cargo test token_parser` 全部通过
- [ ] 手动跑 Codex 对话，能在日志中看到正确的 TokenSnapshot
- [ ] delta 值始终非负
- [ ] 累计 total 值与 Codex 界面显示的 token 数一致（允许 ±5% 误差）
