#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
app_dir="$repo_dir/dist/Sagasu.app"
install_dir="/Applications"
installed_app_dir="$install_dir/Sagasu.app"
home_app_dir="$HOME/Applications/Sagasu.app"

signing_identity() {
  /usr/bin/codesign -dvvv "$1" 2>&1 | /usr/bin/sed -n 's/^Authority=//p' | /usr/bin/head -n 1
}

designated_requirement() {
  /usr/bin/codesign -d -r- "$1" 2>&1 | /usr/bin/sed -n 's/^designated => //p'
}

codesign_identity_available() {
  /usr/bin/security find-identity -v -p codesigning | /usr/bin/grep -Fq "\"$1\""
}

canonical_requirement=""
if [[ -d "$installed_app_dir" ]]; then
  canonical_requirement="$(designated_requirement "$installed_app_dir")"
fi

if [[ -d "$home_app_dir" ]]; then
  printf 'a second Sagasu install was found: %s\n' "$home_app_dir" >&2
  printf 'keep only the canonical install at %s; no app was changed.\n' "$installed_app_dir" >&2
  exit 1
fi

if [[ -d "$installed_app_dir" ]]; then
  canonical_identity="$(signing_identity "$installed_app_dir")"
  if [[ -z "$canonical_requirement" ]]; then
    printf 'the designated requirement could not be read from %s; no app was changed.\n' "$installed_app_dir" >&2
    exit 1
  fi
else
  canonical_identity="${SAGASU_CODE_SIGN_IDENTITY:-}"
fi

if [[ "$canonical_identity" != "Developer ID Application:"* ]] || ! codesign_identity_available "$canonical_identity"; then
  printf 'a usable Developer ID Application identity is required for %s: %s\n' "$installed_app_dir" "$canonical_identity" >&2
  exit 1
fi

if [[ ! -w "$install_dir" ]]; then
  printf 'install directory is not writable: %s\n' "$install_dir" >&2
  exit 1
fi

export SAGASU_CODE_SIGN_IDENTITY="$canonical_identity"

"$repo_dir/Scripts/build_app.sh"

stage_dir="$(/usr/bin/mktemp -d "$install_dir/.Sagasu-install.XXXXXX")"
staged_app_dir="$stage_dir/Sagasu.app"
backup_app_dir="$stage_dir/previous-Sagasu.app"

cleanup() {
  if [[ ! -d "$installed_app_dir" && -d "$backup_app_dir" ]]; then
    /bin/mv "$backup_app_dir" "$installed_app_dir" || true
  fi
  /bin/rm -rf "$stage_dir"
}
trap cleanup EXIT

/usr/bin/ditto "$app_dir" "$staged_app_dir"
/usr/bin/codesign --verify --deep --strict "$staged_app_dir"

if [[ "$(signing_identity "$staged_app_dir")" != "$canonical_identity" ]] ||
  [[ -n "$canonical_requirement" && "$(designated_requirement "$staged_app_dir")" != "$canonical_requirement" ]]; then
  printf 'staged app signing identity or designated requirement does not match %s\n' "$installed_app_dir" >&2
  exit 1
fi

installed_executable="$installed_app_dir/Contents/MacOS/Sagasu"
running_pids=()
while IFS= read -r pid; do
  running_pids+=("$pid")
done < <(/bin/ps -axo pid=,args= | /usr/bin/awk -v executable="$installed_executable" '$2 == executable { print $1 }')

if (( ${#running_pids[@]} > 0 )); then
  /bin/kill -TERM "${running_pids[@]}"
  /bin/sleep 0.5

  for pid in "${running_pids[@]}"; do
    if [[ "$(/bin/ps -p "$pid" -o args= 2>/dev/null | /usr/bin/awk '{ print $1 }')" == "$installed_executable" ]]; then
      printf 'Sagasu did not stop; no app was changed: pid %s\n' "$pid" >&2
      exit 1
    fi
  done
fi

if [[ -d "$installed_app_dir" ]]; then
  /bin/mv "$installed_app_dir" "$backup_app_dir"
fi

if ! /bin/mv "$staged_app_dir" "$installed_app_dir"; then
  if [[ -d "$backup_app_dir" ]]; then
    /bin/mv "$backup_app_dir" "$installed_app_dir" || true
  fi
  exit 1
fi

/bin/rm -rf "$backup_app_dir"
trap - EXIT
/bin/rm -rf "$stage_dir"
/usr/bin/open "$installed_app_dir"

printf '%s\n' "$installed_app_dir"
printf '%s\n' "$installed_app_dir/Contents/MacOS/Sagasu"
