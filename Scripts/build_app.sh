#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
build_dir="$repo_dir/.build/release"
dist_dir="$repo_dir/dist"
app_dir="$dist_dir/Sagasu.app"
contents_dir="$app_dir/Contents"
macos_dir="$contents_dir/MacOS"
resources_dir="$contents_dir/Resources"
entitlements_path="$repo_dir/Packaging/Sagasu.entitlements"
identity="${SAGASU_CODE_SIGN_IDENTITY:-${CODESIGN_IDENTITY:-Apple Development: Kazuhiro Homma (283LEN7F9Y)}}"
version="${SAGASU_VERSION:-1.0.1}"

codesign_identity_available() {
  /usr/bin/security find-identity -v -p codesigning | /usr/bin/grep -Fq "\"$identity\""
}

codesign_app() {
  local sign_target="$1"

  if codesign_identity_available; then
    /usr/bin/codesign \
      --force \
      --deep \
      --options runtime \
      --entitlements "$entitlements_path" \
      --sign "$identity" \
      "$sign_target"
    return
  fi

  /usr/bin/codesign --force --deep --sign - "$sign_target"
}

cd "$repo_dir"
SWIFTPM_DISABLE_SANDBOX=1 /usr/bin/swift build -c release --disable-sandbox

/bin/rm -rf "$app_dir"
/bin/mkdir -p "$macos_dir" "$resources_dir"
/bin/cp "$build_dir/Sagasu" "$macos_dir/Sagasu"
/bin/cp "$repo_dir/App/Info.plist" "$contents_dir/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$contents_dir/Info.plist"
/usr/bin/ditto "$repo_dir/App/Resources" "$resources_dir"
/bin/chmod +x "$macos_dir/Sagasu"

codesign_app "$app_dir"

printf '%s\n' "$app_dir"
printf 'codesign identity: %s\n' "$identity"
