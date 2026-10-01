#!/usr/bin/env bash
set -euo pipefail

# Read-only display/window test; private titles stay in a temporary configuration.
cli="${1:?Pass the window-layout executable path}"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
export WINDOW_LAYOUT_CONFIG="$test_dir/layouts.json"
if ! "$cli" save CurrentDisplaysTest > "$test_dir/save.log"; then
  if grep -q '^No active displays available' "$test_dir/save.log"; then
    echo "SKIP: wake and unlock the desktop before running the live test" >&2
    exit 77
  fi
  cat "$test_dir/save.log" >&2
  exit 1
fi
if [[ "$(jq '.layouts[0].screens | length' "$WINDOW_LAYOUT_CONFIG")" == 0 ]]; then
  echo "SKIP: no active displays; wake and unlock the desktop" >&2
  exit 77
fi
jq '.layouts[0].displayIdentities |= (to_entries | map({uuid: ("replacement-" + (.key | tostring)), vendor: 0, model: 0, serial: 0}))' \
  "$WINDOW_LAYOUT_CONFIG" > "$test_dir/changed.json"
mv "$test_dir/changed.json" "$WINDOW_LAYOUT_CONFIG"
cp "$WINDOW_LAYOUT_CONFIG" "$test_dir/before.json"

if "$cli" apply CurrentDisplaysTest --dry-run > "$test_dir/strict.log"; then
  echo "FAIL: strict apply accepted replacement display identities" >&2
  exit 1
fi
grep -q '^connected displays do not match ' "$test_dir/strict.log"
"$cli" apply CurrentDisplaysTest --current-displays --dry-run > "$test_dir/adapt.log"
expected="$(jq '.layouts[0].screens | length' "$WINDOW_LAYOUT_CONFIG")"
actual="$(grep -c '^mapped saved screen ' "$test_dir/adapt.log" || true)"
[[ "$expected" == "$actual" ]]
grep -q '^would move ' "$test_dir/adapt.log"
if grep -q '^would arrange ' "$test_dir/adapt.log"; then
  echo "FAIL: compatible apply would change the current arrangement" >&2
  exit 1
fi
cmp "$test_dir/before.json" "$WINDOW_LAYOUT_CONFIG"
WINDOW_LAYOUT_CONFIG="$test_dir/after.json" "$cli" save AfterProbe > "$test_dir/after.log"
jq '.layouts[0].screens' "$WINDOW_LAYOUT_CONFIG" > "$test_dir/screens-before.json"
jq '.layouts[0].screens' "$test_dir/after.json" > "$test_dir/screens-after.json"
cmp "$test_dir/screens-before.json" "$test_dir/screens-after.json"

jq '.layouts[0] |= (.screens += [.screens[0]] | .displayIdentities += [.displayIdentities[0]])' \
  "$WINDOW_LAYOUT_CONFIG" > "$test_dir/changed.json"
mv "$test_dir/changed.json" "$WINDOW_LAYOUT_CONFIG"
if "$cli" apply CurrentDisplaysTest --current-displays --dry-run > "$test_dir/count.log"; then
  echo "FAIL: compatible apply accepted a different display count" >&2
  exit 1
fi
grep -q '^cannot adapt ' "$test_dir/count.log"
echo "PASS: $actual replacement displays mapped; mismatched count rejected; arrangement and source configuration unchanged; no windows moved"
