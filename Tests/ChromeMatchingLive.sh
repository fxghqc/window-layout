#!/usr/bin/env bash
set -euo pipefail

# Read-only window test: only a private temporary layout file is modified.
cli="${1:?Pass the window-layout executable path}"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
export WINDOW_LAYOUT_CONFIG="$test_dir/layouts.json"
"$cli" save ChromeMatchingTest > "$test_dir/save.log"
jq '.layouts[0].windows |= (map(select(.bundleID == "com.google.Chrome")) | reverse | map(.title = "Changed tab for regression test"))' \
  "$WINDOW_LAYOUT_CONFIG" > "$test_dir/changed.json"
mv "$test_dir/changed.json" "$WINDOW_LAYOUT_CONFIG"
expected="$(jq '.layouts[0].windows | length' "$WINDOW_LAYOUT_CONFIG")"
identified="$(jq '[.layouts[0].windows[] | select(.identity != null)] | length' "$WINDOW_LAYOUT_CONFIG")"
[[ "$expected" -gt 1 && "$identified" == "$expected" ]]
"$cli" apply ChromeMatchingTest --dry-run > "$test_dir/apply.log"
actual="$(grep -c '^would move .* (window identity)$' "$test_dir/apply.log" || true)"
[[ "$actual" == "$expected" ]]
if grep -q '^skip ' "$test_dir/apply.log"; then
  echo "FAIL: a captured Chrome window was skipped" >&2
  exit 1
fi
echo "PASS: $actual Chrome windows matched by identity after all saved titles changed and order reversed; no windows moved"
