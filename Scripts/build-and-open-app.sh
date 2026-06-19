#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
app_dir="$repo_dir/dist/Sagasu.app"
install_dir="$HOME/Applications"
installed_app_dir="$install_dir/Sagasu.app"

"$repo_dir/Scripts/build_app.sh"

if /usr/bin/pgrep -f "/Sagasu.app/Contents/MacOS/Sagasu" >/dev/null 2>&1; then
  /usr/bin/pkill -f "/Sagasu.app/Contents/MacOS/Sagasu" || true
  /bin/sleep 0.5
fi

/bin/mkdir -p "$install_dir"
/bin/rm -rf "$installed_app_dir"
/usr/bin/ditto "$app_dir" "$installed_app_dir"
/usr/bin/open "$installed_app_dir"

printf '%s\n' "$installed_app_dir"
printf '%s\n' "$installed_app_dir/Contents/MacOS/Sagasu"
