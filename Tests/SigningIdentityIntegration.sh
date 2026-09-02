#!/usr/bin/env bash
set -euo pipefail

project="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
test_keychain="$test_root/signing.keychain"
test_certificate="$test_root/signing-certificate.pem"
test_identity_name="Window Layout Test $(uuidgen)"
original_keychains=()
while IFS= read -r keychain; do
  keychain="${keychain#*\"}"
  keychain="${keychain%\"*}"
  [[ -n "$keychain" ]] && original_keychains+=("$keychain")
done < <(security list-keychains -d user)

cleanup() {
  if [[ "${#original_keychains[@]}" -gt 0 ]]; then
    security list-keychains -d user -s "${original_keychains[@]}" >/dev/null 2>&1 || true
  fi
  if [[ -s "$test_certificate" ]]; then
    security remove-trusted-cert "$test_certificate" >/dev/null 2>&1 || true
  fi
  security delete-keychain "$test_keychain" >/dev/null 2>&1 || true
  rm -rf "$test_root"
}
trap cleanup EXIT

security create-keychain -p window-layout-test "$test_keychain"
security unlock-keychain -p window-layout-test "$test_keychain"
security set-keychain-settings -lut 3600 "$test_keychain"
security list-keychains -d user -s "$test_keychain" "${original_keychains[@]}"

WINDOW_LAYOUT_IDENTITY_NAME="$test_identity_name" \
WINDOW_LAYOUT_KEYCHAIN="$test_keychain" \
  "$project/scripts/create-signing-identity.sh" --yes
security find-certificate \
  -c "$test_identity_name" \
  -p "$test_keychain" > "$test_certificate"

test_identity="$(
  security find-identity -v -p codesigning "$test_keychain" |
    awk 'NR == 1 { print $2 }'
)"

WINDOW_LAYOUT_HOME="$test_root/home" \
WINDOW_LAYOUT_KEYCHAIN="$test_keychain" \
WINDOW_LAYOUT_SIGNING_IDENTITY="$test_identity" \
  "$project/scripts/install.sh" --no-launch

app="$test_root/home/Applications/Window Layout.app"
cli="$test_root/home/.local/bin/window-layout"
app_requirement="$(codesign -d -r- "$app" 2>&1)"
cli_requirement="$(codesign -d -r- "$cli" 2>&1)"

[[ "$app_requirement" == *'identifier "io.github.fxghqc.window-layout"'* ]]
[[ "$app_requirement" == *'certificate root'* ]]
[[ "$app_requirement" != *'cdhash'* ]]
[[ "$cli_requirement" == *'identifier "io.github.fxghqc.window-layout.cli"'* ]]
[[ "$cli_requirement" == *'certificate root'* ]]
[[ "$cli_requirement" != *'cdhash'* ]]

codesign --verify --deep --strict "$app"
codesign --verify --strict "$cli"
echo "PASS: app and CLI have stable certificate-based requirements"
