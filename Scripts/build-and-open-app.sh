#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build"
APP_DIR="$BUILD_DIR/Sagasu.app"
INSTALL_DIR="$HOME/Applications"
INSTALLED_APP_DIR="$INSTALL_DIR/Sagasu.app"
EXECUTABLE_PATH="$BUILD_DIR/arm64-apple-macosx/debug/Sagasu"
BUNDLED_EXECUTABLE_PATH="$APP_DIR/Contents/MacOS/Sagasu"
CODE_SIGN_IDENTITY="${SAGASU_CODE_SIGN_IDENTITY:-Apple Development: Kazuhiro Homma (283LEN7F9Y)}"

codesign_app() {
  local app_path="$1"
  local identity="$CODE_SIGN_IDENTITY"

  if /usr/bin/security find-identity -v -p codesigning | /usr/bin/grep -Fq "\"$identity\""; then
    /usr/bin/codesign --force --deep --sign "$identity" "$app_path"
    return
  fi

  /usr/bin/codesign --force --deep --sign - "$app_path"
}

cd "$ROOT_DIR"
/usr/bin/swift build

/bin/mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
/bin/cp "$ROOT_DIR/App/Info.plist" "$APP_DIR/Contents/Info.plist"
/bin/cp "$EXECUTABLE_PATH" "$BUNDLED_EXECUTABLE_PATH"
/usr/bin/ditto "$ROOT_DIR/App/Resources" "$APP_DIR/Contents/Resources"
/bin/chmod +x "$BUNDLED_EXECUTABLE_PATH"

codesign_app "$APP_DIR"

if /usr/bin/pgrep -f "/Sagasu.app/Contents/MacOS/Sagasu" >/dev/null 2>&1; then
  /usr/bin/pkill -f "/Sagasu.app/Contents/MacOS/Sagasu" || true
  /bin/sleep 0.5
fi

/bin/mkdir -p "$INSTALL_DIR"
/usr/bin/ditto "$APP_DIR" "$INSTALLED_APP_DIR"
/usr/bin/open "$INSTALLED_APP_DIR"

printf '%s\n' "$APP_DIR"
printf '%s\n' "$BUNDLED_EXECUTABLE_PATH"
printf '%s\n' "$INSTALLED_APP_DIR"
printf '%s\n' "$INSTALLED_APP_DIR/Contents/MacOS/Sagasu"
printf 'codesign identity: %s\n' "$CODE_SIGN_IDENTITY"
