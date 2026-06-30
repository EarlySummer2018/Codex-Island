#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${1:-build/Release/CodexIsland.app}"
VERSION="${VERSION:-${GITHUB_REF_NAME:-0.1.0}}"
VERSION="${VERSION#v}"
ARTIFACT_SUFFIX="${ARTIFACT_SUFFIX:-}"
CLEAN_DIST="${CLEAN_DIST:-1}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
STAGE_DIR="$DIST_DIR/stage${ARTIFACT_SUFFIX}"
APP_NAME="CodexIsland"
STAGED_APP="$STAGE_DIR/$APP_NAME.app"
APPLICATIONS_LINK="$STAGE_DIR/Applications"
APP_SIGN_IDENTITY="${MACOS_APP_SIGN_IDENTITY:-}"
INSTALLER_SIGN_IDENTITY="${MACOS_INSTALLER_SIGN_IDENTITY:-}"
APPLE_ID="${APPLE_ID:-}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:-}"
APPLE_APP_SPECIFIC_PASSWORD="${APPLE_APP_SPECIFIC_PASSWORD:-}"

if [ ! -d "$APP_PATH" ]; then
  echo "App bundle not found: $APP_PATH" >&2
  exit 1
fi

if [ "$CLEAN_DIST" = "1" ]; then
  rm -rf "$DIST_DIR"
fi
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"
cp -R "$APP_PATH" "$STAGED_APP"

has_notary_credentials() {
  [ -n "$APPLE_ID" ] \
    && [ -n "$APPLE_TEAM_ID" ] \
    && [ -n "$APPLE_APP_SPECIFIC_PASSWORD" ]
}

notarize_artifact() {
  local artifact_path="$1"
  echo "Submitting $(basename "$artifact_path") for notarization..."
  xcrun notarytool submit "$artifact_path" \
    --apple-id "$APPLE_ID" \
    --team-id "$APPLE_TEAM_ID" \
    --password "$APPLE_APP_SPECIFIC_PASSWORD" \
    --wait
}

staple_artifact() {
  local artifact_path="$1"
  xcrun stapler staple "$artifact_path"
  xcrun stapler validate "$artifact_path"
}

sign_app_if_configured() {
  if [ -z "$APP_SIGN_IDENTITY" ]; then
    echo "MACOS_APP_SIGN_IDENTITY is not set; leaving app ad-hoc signed."
    return
  fi

  echo "Signing app with: $APP_SIGN_IDENTITY"
  if [ -f "$STAGED_APP/Contents/Resources/codex-watcher" ]; then
    codesign --force --options runtime --timestamp \
      --sign "$APP_SIGN_IDENTITY" \
      "$STAGED_APP/Contents/Resources/codex-watcher"
  fi

  codesign --force --deep --options runtime --timestamp \
    --entitlements "$ROOT_DIR/CodexIsland/CodexIsland.entitlements" \
    --sign "$APP_SIGN_IDENTITY" \
    "$STAGED_APP"
  codesign --verify --deep --strict --verbose=2 "$STAGED_APP"
}

notarize_app_if_configured() {
  if ! has_notary_credentials; then
    echo "Apple notarization credentials are not set; skipping notarization."
    return
  fi

  if [ -z "$APP_SIGN_IDENTITY" ]; then
    echo "Notarization credentials are set, but MACOS_APP_SIGN_IDENTITY is missing." >&2
    exit 1
  fi

  local app_notary_zip="$DIST_DIR/$APP_NAME-$VERSION${ARTIFACT_SUFFIX}-app-notary.zip"
  ditto -c -k --keepParent "$STAGED_APP" "$app_notary_zip"
  notarize_artifact "$app_notary_zip"
  staple_artifact "$STAGED_APP"
  rm -f "$app_notary_zip"
}

sign_app_if_configured
notarize_app_if_configured

ZIP_PATH="$DIST_DIR/$APP_NAME-$VERSION-macOS${ARTIFACT_SUFFIX}.zip"
DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION-macOS${ARTIFACT_SUFFIX}.dmg"
PKG_PATH="$DIST_DIR/$APP_NAME-$VERSION-macOS${ARTIFACT_SUFFIX}.pkg"

ditto -c -k --keepParent "$STAGED_APP" "$ZIP_PATH"

# Show the standard drag-to-Applications target when users open the DMG.
ln -s /Applications "$APPLICATIONS_LINK"

hdiutil create \
  -volname "Codex Island" \
  -srcfolder "$STAGE_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

if [ -n "$APP_SIGN_IDENTITY" ]; then
  codesign --force --timestamp --sign "$APP_SIGN_IDENTITY" "$DMG_PATH"
  codesign --verify --verbose=2 "$DMG_PATH"
fi

if [ -n "$INSTALLER_SIGN_IDENTITY" ]; then
  pkgbuild \
    --component "$STAGED_APP" \
    --install-location /Applications \
    --sign "$INSTALLER_SIGN_IDENTITY" \
    "$PKG_PATH"
else
  pkgbuild \
    --component "$STAGED_APP" \
    --install-location /Applications \
    "$PKG_PATH"
fi

if has_notary_credentials; then
  notarize_artifact "$DMG_PATH"
  staple_artifact "$DMG_PATH"

  if [ -n "$INSTALLER_SIGN_IDENTITY" ]; then
    notarize_artifact "$PKG_PATH"
    staple_artifact "$PKG_PATH"
  else
    echo "MACOS_INSTALLER_SIGN_IDENTITY is not set; skipping PKG notarization."
  fi
fi

rm -rf "$STAGE_DIR"
echo "Release artifacts written to $DIST_DIR"
