# Codex Island

[English](README.en.md)

Codex Island 是一个面向 Codex Desktop 的 macOS 顶部胶囊与桌面宠物应用。它监听本机 Codex 会话的状态和 token 元数据，在屏幕顶部持续显示当前状态，并将累计使用量转化为宠物等级和十阶段外观。

## 核心功能

- 顶部常驻胶囊，展示当前会话的 `IN`、`CACHE`、`OUT` 和 `TOTAL`。
- 识别空闲、运行中、等待输入、可供审阅和错误状态，并区分思考、命令执行、文件修改、网页检索和回复生成。
- 根据本机全部 Codex 会话的累计 token 计算宠物等级和成长进度。
- 支持大/小胶囊、桌宠模式、长按拖动和按显示器保存位置。
- 支持十阶段自定义宠物，胶囊、展开面板、桌宠和漫游宠物统一生效。
- 支持从设置面板或状态栏菜单一键重启应用，重新加载自定义宠物。
- Rust sidecar 只处理 token 与状态元数据，不转发用户输入或 AI 回复正文。

## 自定义十阶段宠物

应用首次启动时会自动创建：

```text
${CODEX_HOME:-$HOME/.codex}/pets/codex-island-stages/
├── 01-lv00-09/
├── 02-lv10-19/
├── 03-lv20-29/
├── 04-lv30-39/
├── 05-lv40-49/
├── 06-lv50-59/
├── 07-lv60-69/
├── 08-lv70-79/
├── 09-lv80-89/
└── 10-lv90-100/
```

可以从状态栏菜单或设置面板点击“自定义宠物”直接打开该目录。每个阶段目录放入一个标准 Codex 宠物包：

```text
01-lv00-09/
├── pet.json
└── spritesheet.png（或 spritesheet.webp）
```

`pet.json` 示例：

```json
{
  "id": "ruby",
  "displayName": "Ruby",
  "description": "A fluffy orange-and-white cat.",
  "spritesheetPath": "spritesheet.webp"
}
```

图集必须满足 Codex 宠物规范：

- PNG 或 WebP，宽度固定为 `1536`，高度至少为 `1872` 且必须是 `208` 的整数倍。
- 每行最多 8 帧，每个单元格 `192x208`，图集至少包含当前支持的 9 行动画。
- 每个槽位都允许透明；应用会逐行识别实际非透明帧并跳过透明槽位，不要求各行动画使用固定帧数。整行为空时回退到第一阶段或内置宠物，超过 9 行的扩展动画行由当前版本忽略。
- `spritesheetPath` 必须是阶段目录内的安全相对路径，扩展名必须与实际 PNG/WebP 编码一致。

资源选择顺序：

1. 当前阶段配置有效时，使用当前阶段的自定义宠物。
2. 当前阶段未配置或无效，但第一阶段有效时，继承第一阶段的自定义宠物。
3. 第一阶段也未配置或无效时，使用当前等级原本对应的内置默认宠物。

自定义资源会在应用启动时扫描。替换文件后，可以从设置面板点击重启图标，或从状态栏菜单选择“重启应用”加载新资源；不支持运行中热更新。

## 环境要求

- macOS 13 或更新版本
- Xcode 26.5 或兼容版本
- Rust toolchain
- XcodeGen 2.45.4 或更新版本

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

常用验证命令：

```bash
make test-rust
make test-ipc
make test-app-runtime
make verify
```

## 架构与隐私

```text
Codex App-Server / ~/.codex/sessions/**/*.jsonl
                    |
                    v
          codex-watcher (Rust)
                    |
                    v
             Unix Socket IPC
                    |
                    v
        CodexIsland.app (Swift/AppKit/SwiftUI)
```

sidecar 优先消费 Codex App-Server 事件，必要时回退到脱敏后的本地 JSONL 元数据。它不会修改 Codex 会话文件，也不会向 Swift App 转发提示词、用户消息或回复正文。

## 发布流程

发布版本以 `project.yml` 中的 `MARKETING_VERSION` 为准。版本 tag 必须与它一致：

```bash
git tag v1.2.1
git push origin v1.2.1
```

GitHub Actions 会验证版本、运行 Rust 与 Swift 测试、构建 universal 与 x86_64 macOS 应用，并生成 `.zip`、`.dmg`、`.pkg`、SHA-256 校验文件和中文 Release Notes。

如需 Developer ID 签名和 Apple 公证，请配置：

- `MACOS_CERTIFICATE_BASE64`
- `MACOS_CERTIFICATE_PASSWORD`
- `KEYCHAIN_PASSWORD`
- `MACOS_APP_SIGN_IDENTITY`
- `MACOS_INSTALLER_SIGN_IDENTITY`
- `APPLE_ID`
- `APPLE_TEAM_ID`
- `APPLE_APP_SPECIFIC_PASSWORD`

未配置这些 secrets 时，构建使用 ad-hoc 签名，仅适合本地测试。对可信的未公证构建可使用：

```bash
xattr -dr com.apple.quarantine /Applications/CodexIsland.app
```

## 当前状态

项目持续开发中。问题和功能建议请通过 GitHub Issues 提交。
