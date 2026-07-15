# Codex Island

[中文](README.md)

Codex Island is a macOS top-screen capsule and desktop pet for Codex Desktop. It watches local Codex state and token metadata, keeps the current activity visible, and turns cumulative usage into pet levels and ten visual stages.

## Features

- Persistent top capsule with current-session `IN`, `CACHE`, `OUT`, and `TOTAL` counters.
- Runtime states for idle, running, waiting for input, ready for review, and errors, with activity details for reasoning, commands, file changes, web search, and reply generation.
- Pet levels and evolution based on cumulative usage across all local Codex sessions.
- Large and small capsule styles, desktop pet mode, long-press dragging, and per-display position persistence.
- Idle roaming is deliberately infrequent: after moving, the pet plays its waiting animation for 20–40 seconds. Disabling Free Movement keeps it at its current position with state animations and in-place reactions.
- Right-click the pet to open Codex, toggle Free Movement, open Custom Pets or Settings, or put the pet away.
- The pet only receives pointer input near its visible body and level badge, so transparent window margins no longer block apps underneath.
- Hover the desktop pet and drag its lightweight upper-right handle, or use the mouse wheel/trackpad, to resize the pet from `50%–200%` while keeping the level badge at a fixed size; pet size and position are restored after relaunch.
- Ten-stage custom pets shared by the capsule, expanded panel, desktop pet, and roaming pet.
- One-click app restart from Settings or the menu bar to reload custom pets.
- A Rust sidecar that processes token and state metadata without forwarding prompts, user messages, or assistant response text.

## Ten-Stage Custom Pets

The app creates this directory tree on first launch:

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

Choose **Custom Pets** from the menu bar or Settings to open this directory. Each stage accepts one standard Codex pet package:

```text
01-lv00-09/
├── pet.json
└── spritesheet.png (or spritesheet.webp)
```

Example manifest:

```json
{
  "id": "ruby",
  "displayName": "Ruby",
  "description": "A fluffy orange-and-white cat.",
  "spritesheetPath": "spritesheet.webp"
}
```

The atlas may be PNG or WebP. It must be 1536 pixels wide and at least 1872 pixels high, with the height aligned to 208-pixel rows. Each row has at most 8 `192x208` frame slots. The app detects non-transparent frames per row and skips transparent slots instead of requiring a fixed frame count. A fully transparent row falls back to stage one or the bundled pet, and animation rows after the first 9 are ignored. `spritesheetPath` must be a safe relative path inside the stage directory, and its extension must match the actual PNG/WebP encoding.

Resource priority:

1. Use the current stage when its custom package is valid.
2. Otherwise inherit the valid stage-one custom pet.
3. If stage one is also missing or invalid, use the built-in default pet for the current level.

Custom resources are scanned at startup. After replacing files, use the restart icon in Settings or choose **Restart App** from the menu bar to load them; hot reload is intentionally not supported.

## Requirements

- macOS 13 or later
- Xcode 26.5 or compatible command line tools
- Rust toolchain
- XcodeGen 2.45.4 or later

```bash
brew install xcodegen
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```

## Development

```bash
git clone https://github.com/EarlySummer2018/Codex-Island.git
cd Codex-Island
make bootstrap
make build-macos
open ~/Library/Developer/Xcode/DerivedData/CodexIsland-*/Build/Products/Debug/CodexIsland.app
```

Useful verification commands:

```bash
make test-rust
make test-ipc
make test-app-runtime
make verify
```

## Architecture and Privacy

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

The sidecar prefers Codex App-Server events and falls back to sanitized local JSONL metadata when needed. It does not modify Codex session files or forward prompt, user-message, or assistant-response content to the Swift app.

## Releases

The release version comes from `MARKETING_VERSION` in `project.yml`. The version tag must match it:

```bash
git tag v1.2.2
git push origin v1.2.2
```

GitHub Actions validates the version, runs Rust and Swift tests, builds universal and x86_64 macOS applications, and publishes `.zip`, `.dmg`, `.pkg`, SHA-256 checksums, and Chinese release notes.

Developer ID signing and notarization use these repository secrets:

- `MACOS_CERTIFICATE_BASE64`
- `MACOS_CERTIFICATE_PASSWORD`
- `KEYCHAIN_PASSWORD`
- `MACOS_APP_SIGN_IDENTITY`
- `MACOS_INSTALLER_SIGN_IDENTITY`
- `APPLE_ID`
- `APPLE_TEAM_ID`
- `APPLE_APP_SPECIFIC_PASSWORD`

Without these secrets, release artifacts are ad-hoc signed and intended for local testing.

## Status

The project is under active development. Please report bugs and feature requests through GitHub Issues.
