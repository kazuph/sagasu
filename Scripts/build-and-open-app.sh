#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build"
APP_DIR="$BUILD_DIR/Sagasu.app"
EXECUTABLE_PATH="$BUILD_DIR/arm64-apple-macosx/debug/Sagasu"
BUNDLED_EXECUTABLE_PATH="$APP_DIR/Contents/MacOS/Sagasu"

cd "$ROOT_DIR"
/usr/bin/swift build

/bin/mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
/bin/cp "$ROOT_DIR/App/Info.plist" "$APP_DIR/Contents/Info.plist"
/bin/cp "$EXECUTABLE_PATH" "$BUNDLED_EXECUTABLE_PATH"
/usr/bin/ditto "$ROOT_DIR/App/Resources" "$APP_DIR/Contents/Resources"
/bin/chmod +x "$BUNDLED_EXECUTABLE_PATH"

/usr/bin/codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true

printf '%s\n' "$APP_DIR"
printf '%s\n' "$BUNDLED_EXECUTABLE_PATH"
