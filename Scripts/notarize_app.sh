#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
app_path="${1:-$repo_dir/dist/Sagasu.app}"
notary_key_path="${SAGASU_NOTARY_KEY_PATH:?SAGASU_NOTARY_KEY_PATH is required}"
notary_key_id="${SAGASU_NOTARY_KEY_ID:?SAGASU_NOTARY_KEY_ID is required}"
notary_issuer_id="${SAGASU_NOTARY_ISSUER_ID:?SAGASU_NOTARY_ISSUER_ID is required}"
notary_dir="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/sagasu-notary.XXXXXX")"
submission_path="$notary_dir/Sagasu.zip"

cleanup() {
  /bin/rm -rf "$notary_dir"
}
trap cleanup EXIT

if [[ "${SAGASU_DISTRIBUTION_BUILD:-0}" != "1" ]]; then
  printf 'notarization requires SAGASU_DISTRIBUTION_BUILD=1\n' >&2
  exit 1
fi

if [[ ! -d "$app_path" ]]; then
  printf 'app bundle does not exist: %s\n' "$app_path" >&2
  exit 1
fi

/usr/bin/ditto -c -k --keepParent "$app_path" "$submission_path"
/usr/bin/xcrun notarytool submit "$submission_path" \
  --key "$notary_key_path" \
  --key-id "$notary_key_id" \
  --issuer "$notary_issuer_id" \
  --wait
/usr/bin/xcrun stapler staple "$app_path"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$app_path"
/usr/sbin/spctl --assess --type execute --verbose=4 "$app_path"
/usr/bin/xcrun stapler validate "$app_path"

printf '%s\n' "$app_path"
