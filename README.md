# Codex Island

Codex Island is a small macOS companion for Codex Desktop. It watches local Codex session data, shows a persistent top-screen capsule, and turns token usage into a tiny evolving pixel pet.

[中文文档](README.zh-CN.md)

## Features

- Persistent top capsule with current-session `IN`, `CACHE`, `OUT`, and `TOTAL` token counters.
- Pixel pet that reacts to Codex states: idle, thinking, streaming, waiting for input, and error.
- Pet evolution driven by global token usage across all local Codex sessions.
- Long-press dragging with per-display position persistence.
- Menu bar controls for capsule size, language, cache folders, Codex activation, updates, and app visibility.
- Rust sidecar that reads only token and state metadata from `~/.codex/sessions`, without forwarding prompt or response text.

## Requirements

- macOS 13 or later
- Xcode 26.5 or compatible Xcode command line tools
- Rust toolchain
- XcodeGen

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

Useful commands:

```bash
make test-rust
make test-ipc
make test-app-runtime
make verify
```

## Architecture

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

The Rust sidecar tails `~/.codex/sessions/**/*.jsonl`, sanitizes events, emits current-session token snapshots, aggregates global token usage, and broadcasts newline-delimited JSON over a Unix socket. The Swift app renders the floating capsule, menu bar controls, token counters, pet animation, and awaiting-input alerts.

## Privacy

Codex Island is designed to read metadata only:

- It keeps token totals and state events.
- It does not forward assistant text deltas.
- It does not forward user message content.
- It does not write to Codex session files.

## Packaging

GitHub Actions builds release artifacts on version tags:

```bash
git tag v0.1.0
git push origin v0.1.0
```

The workflow produces a zipped `.app`, a `.dmg`, and a `.pkg` installer for macOS.

### Gatekeeper And Notarization

Unsigned or ad-hoc signed downloads are blocked by macOS Gatekeeper with:

```text
Apple cannot verify that "CodexIsland" is free of malware.
```

For local testing, open the app with Control-click -> Open, or remove quarantine only for a build you trust:

```bash
xattr -dr com.apple.quarantine /Applications/CodexIsland.app
```

For public releases, configure Developer ID signing and Apple notarization in GitHub Actions. Add these repository secrets:

- `MACOS_CERTIFICATE_BASE64`: base64-encoded `.p12` containing Developer ID Application, and preferably Developer ID Installer, certificates with private keys.
- `MACOS_CERTIFICATE_PASSWORD`: password for the `.p12`.
- `KEYCHAIN_PASSWORD`: temporary CI keychain password.
- `MACOS_APP_SIGN_IDENTITY`: for example `Developer ID Application: Your Name (TEAMID)`.
- `MACOS_INSTALLER_SIGN_IDENTITY`: for example `Developer ID Installer: Your Name (TEAMID)`.
- `APPLE_ID`: Apple ID used for notarization.
- `APPLE_TEAM_ID`: Apple Developer Team ID.
- `APPLE_APP_SPECIFIC_PASSWORD`: app-specific password for notarization.

When these secrets are present, the release workflow signs the app, notarizes and staples it, then creates signed/notarized DMG and PKG artifacts.

## Status

This project is in active early development. Builds without the Apple secrets above are ad-hoc signed and intended for local testing only.
