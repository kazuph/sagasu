#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
version="${1:-${GITHUB_REF_NAME:-1.0.2}}"
version="${version#v}"
dist_dir="$repo_dir/dist"
app_path="$dist_dir/Sagasu.app"
release_dir="$dist_dir/release"
dmg_root="$release_dir/dmg-root"

/bin/rm -rf "$release_dir"
/bin/mkdir -p "$release_dir"
trap '/bin/rm -rf "$dmg_root"' EXIT

SAGASU_VERSION="$version" "$repo_dir/Scripts/build_app.sh" >/dev/null

zip_path="$release_dir/Sagasu-${version}.zip"
dmg_path="$release_dir/Sagasu-${version}.dmg"
checksum_path="$release_dir/checksums.txt"

/usr/bin/ditto -c -k --keepParent "$app_path" "$zip_path"
/bin/mkdir -p "$dmg_root"
/bin/cp -R "$app_path" "$dmg_root/"
/bin/ln -s /Applications "$dmg_root/Applications"
/usr/bin/hdiutil create \
  -volname "Sagasu" \
  -srcfolder "$dmg_root" \
  -ov \
  -format UDZO \
  "$dmg_path" >/dev/null
/bin/rm -rf "$dmg_root"

(
  cd "$release_dir"
  /usr/bin/shasum -a 256 "Sagasu-${version}.zip" "Sagasu-${version}.dmg" > "$checksum_path"
)

printf '%s\n' "$release_dir"
