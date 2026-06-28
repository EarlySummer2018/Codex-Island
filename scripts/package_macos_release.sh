#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${1:-build/Release/CodexIsland.app}"
VERSION="${VERSION:-${GITHUB_REF_NAME:-0.1.0}}"
VERSION="${VERSION#v}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
STAGE_DIR="$DIST_DIR/stage"
APP_NAME="CodexIsland"

if [ ! -d "$APP_PATH" ]; then
  echo "App bundle not found: $APP_PATH" >&2
  exit 1
fi

rm -rf "$DIST_DIR"
mkdir -p "$STAGE_DIR"
cp -R "$APP_PATH" "$STAGE_DIR/$APP_NAME.app"

ditto -c -k --keepParent "$STAGE_DIR/$APP_NAME.app" "$DIST_DIR/$APP_NAME-$VERSION-macOS.zip"

hdiutil create \
  -volname "Codex Island" \
  -srcfolder "$STAGE_DIR" \
  -ov \
  -format UDZO \
  "$DIST_DIR/$APP_NAME-$VERSION-macOS.dmg"

pkgbuild \
  --component "$STAGE_DIR/$APP_NAME.app" \
  --install-location /Applications \
  "$DIST_DIR/$APP_NAME-$VERSION-macOS.pkg"

rm -rf "$STAGE_DIR"
echo "Release artifacts written to $DIST_DIR"
