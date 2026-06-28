# 01 — 工程初始化

> 目标：建立可运行的 macOS 原生菜单栏空壳工程，并确认 Codex 本地数据路径可访问。

---

## 需求对齐

本阶段对应 `demand.md` 里的 M1：基础工程搭建。

01 只负责：

- SwiftUI + AppKit macOS App 空壳可构建、可启动
- 菜单栏 `NSStatusItem` 备用入口出现
- Rust sidecar 工程创建并可运行
- `~/.codex/sessions/` 可访问性检查
- 本地开发签名配置可用

01 不负责：

- JSONL 实时监听（02）
- Token 解析与差分（03）
- 状态机（04）
- 刘海窗口、宠物、通知和 Token UI（05-08）

---

## 前置检查

```bash
# Codex sessions 目录
ls ~/.codex/sessions/

# Codex Desktop App
ls /Applications/Codex.app

# macOS 版本，最低需要 Ventura 13.0
sw_vers -productVersion

# Rust 工具链，最低建议 1.78+
rustc --version
cargo --version

# Xcode，最低建议 15.0+
xcodebuild -version

# 预览真实 JSONL
find ~/.codex/sessions -name "*.jsonl" | head -3 | xargs head -5
```

当前机器如果 `rustc` / `cargo` 不在默认 PATH，可先使用：

```bash
export PATH="$HOME/.cargo/bin:$PATH"
```

---

## 初始化方式

Rust sidecar 使用官方脚手架：

```bash
cargo new codex-watcher
```

macOS Xcode 工程使用 XcodeGen 生成，避免手写 `.xcodeproj`：

```bash
brew install xcodegen
xcodegen generate
```

仓库提供统一入口：

```bash
make bootstrap
make verify
```

---

## 当前目录结构

```text
Codex-Island/
├── CodexIsland.xcodeproj          # 由 project.yml 生成
├── CodexIsland/                   # Swift 主 App
│   ├── App/
│   │   ├── AppDelegate.swift
│   │   └── CodexIslandApp.swift
│   ├── Assets.xcassets/
│   ├── CodexIsland.entitlements
│   └── Info.plist
├── codex-watcher/                 # Rust sidecar
│   ├── Cargo.toml
│   └── src/
├── docs/
├── Makefile
└── project.yml
```

---

## 签名与权限

本地开发和本地 `.dmg` 打包不需要 Apple Developer Account。

当前工程使用 ad-hoc / Sign to Run Locally：

```yaml
CODE_SIGN_STYLE: Manual
CODE_SIGN_IDENTITY: "-"
```

阶段一按 PRD 的最小权限原则设计：

- App Sandbox 关闭，因为需要读取 `~/.codex/sessions/`
- 不申请 Apple Events 权限
- 不申请 Accessibility 权限
- 不写入任何 Codex 文件

后续如果要面向外部分发，才需要 Developer ID 签名和 Notarization；这不是 01 的本地开发前置条件。

---

## 完成标准

- [x] `make bootstrap` 能生成 `CodexIsland.xcodeproj`
- [x] Rust sidecar 能编译运行
- [x] Xcode 工程能编译并运行
- [x] 菜单栏出现 CPU 图标
- [x] `~/.codex/sessions/` 目录存在且 `.jsonl` 文件可读

---

## 常见问题

**Q: 本地开发是否需要 Apple Developer Account？**
A: 不需要。本地构建、运行和生成本地 `.dmg` 都可以使用 ad-hoc 签名。

**Q: 为什么关闭 App Sandbox？**
A: Codex sessions 默认在 `~/.codex/sessions/`，沙盒 App 无法直接读取该目录。PRD 也明确阶段一不走 App Store 分发。

**Q: 找不到 `~/.codex/sessions/` 怎么办？**
A: 先运行一次 Codex 对话，例如 `codex "hello"`，等 sessions 目录生成后再检查。
