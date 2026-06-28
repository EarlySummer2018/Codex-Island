.PHONY: bootstrap generate-xcode build-rust test-rust test-ipc test-app-runtime run-watcher build-macos build-release package-release verify

export PATH := $(HOME)/.cargo/bin:$(PATH)

bootstrap:
	@command -v xcodegen >/dev/null || brew install xcodegen
	@command -v cargo >/dev/null || (echo "Rust toolchain is required. Install it from https://rustup.rs/" && exit 1)
	$(MAKE) generate-xcode

generate-xcode:
	xcodegen generate

build-rust:
	cd codex-watcher && cargo build

test-rust:
	cd codex-watcher && cargo test

test-ipc: build-rust
	python3 scripts/ipc_smoke_test.py codex-watcher/target/debug/codex-watcher

test-app-runtime: build-macos
	python3 scripts/app_runtime_smoke_test.py

run-watcher:
	cd codex-watcher && RUST_LOG=debug cargo run

build-macos:
	xcodebuild -project CodexIsland.xcodeproj -scheme CodexIsland -configuration Debug -destination 'platform=macOS' CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES build

build-release:
	xcodebuild -project CodexIsland.xcodeproj -scheme CodexIsland -configuration Release -destination 'generic/platform=macOS' CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES SYMROOT='$(PWD)/build' build

package-release: build-release
	scripts/package_macos_release.sh build/Release/CodexIsland.app

verify: test-rust test-ipc build-macos
