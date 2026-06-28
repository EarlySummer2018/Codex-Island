# Codex Island

Codex Island 是一个 macOS 顶部胶囊 companion app：它监听本机 Codex Desktop 的会话状态，用常驻胶囊展示当前会话 token，并让一个像素宠物根据所有会话的累计 token 逐步进化。

[English README](README.md)

## 功能

- 顶部常驻胶囊，展示当前 active session 的 `IN` / `CACHE` / `OUT` / `TOTAL`。
- 像素宠物跟随 Codex 状态变化：空闲、思考、输出、等待用户、错误。
- 宠物进化基于本机所有 Codex sessions 的全局累计 token，不是单会话 token。
- 胶囊支持长按拖动，并按屏幕保存位置。
- 顶部状态栏菜单支持切换大/小胶囊、切换中英文、打开缓存目录、打开 Codex、显示隐藏胶囊和退出。
- Rust sidecar 只读取 token 和状态元数据，不转发用户输入正文或 AI 回复正文。

## 环境要求

- macOS 13 或更新版本
- Xcode 26.5 或兼容版本
- Rust toolchain
- XcodeGen

```bash
brew install xcodegen
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```

## 本地开发

```bash
git clone https://github.com/EarlySummer2018/Codex-Island.git
cd Codex-Island
make bootstrap
make build-macos
open ~/Library/Developer/Xcode/DerivedData/CodexIsland-*/Build/Products/Debug/CodexIsland.app
```

常用命令：

```bash
make test-rust
make test-ipc
make test-app-runtime
make verify
```

## 架构

```text
Codex sessions JSONL
        |
        v
codex-watcher (Rust)
        |
        v
Unix socket IPC
        |
        v
CodexIsland.app (Swift/AppKit/SwiftUI)
```

Rust sidecar 监听 `~/.codex/sessions/**/*.jsonl`，对事件做脱敏，输出当前会话 token 快照，聚合全局 token 使用量，并通过 Unix Socket 广播 JSON 行。Swift 主 App 负责渲染胶囊、状态栏菜单、token 数字、宠物动画和等待用户输入提醒。

## 隐私边界

Codex Island 只读取必要元数据：

- 保留 token totals 和状态事件。
- 不转发 AI 回复文本增量。
- 不转发用户消息正文。
- 不写入 Codex session 文件。

## 发布打包

推送版本 tag 后，GitHub Actions 会自动构建 macOS 安装包：

```bash
git tag v0.1.0
git push origin v0.1.0
```

流水线会生成 zipped `.app`、`.dmg` 和 `.pkg` 三类产物。

## 当前状态

项目处于早期开发阶段。当前 release 默认使用 ad-hoc signing，适合本地安装和试用；后续可通过 GitHub Actions secrets 接入 Developer ID 签名和 notarization。
