#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_HOME="${WINDOW_LAYOUT_HOME:-$HOME}"
APP_SUPPORT="$INSTALL_HOME/Library/Application Support/window-layout"
CLI_DIR="$INSTALL_HOME/.local/bin"
APP_DIR="$INSTALL_HOME/Applications/Window Layout.app"
STAGING="$(mktemp -d)/Window Layout.app"
SIGNING_IDENTITY="${WINDOW_LAYOUT_SIGNING_IDENTITY:-Window Layout Local Code Signing}"

cleanup() {
  rm -rf "$(dirname "$STAGING")"
}
trap cleanup EXIT

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

cd "$ROOT"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

if [[ "$SIGNING_IDENTITY" == "Window Layout Local Code Signing" ]]; then
  "$ROOT/scripts/create-signing-identity.sh"
elif [[ "$SIGNING_IDENTITY" != "-" ]] &&
     ! security find-identity -v -p codesigning 2>/dev/null | grep -Fq "$SIGNING_IDENTITY"; then
    echo "Code-signing identity not found: $SIGNING_IDENTITY" >&2
    exit 1
fi

mkdir -p "$CLI_DIR" "$APP_SUPPORT" "$STAGING/Contents/MacOS"
install -m 755 "$BIN_DIR/window-layout" "$CLI_DIR/window-layout"
install -m 755 "$BIN_DIR/window-layout-menu" "$STAGING/Contents/MacOS/Window Layout"
install -m 644 "$ROOT/Resources/Info.plist" "$STAGING/Contents/Info.plist"

codesign \
  --force \
  --sign "$SIGNING_IDENTITY" \
  --identifier io.github.fxghqc.window-layout.cli \
  "$CLI_DIR/window-layout"
codesign --force --deep --sign "$SIGNING_IDENTITY" "$STAGING"
codesign --verify --strict "$CLI_DIR/window-layout"
codesign --verify --deep --strict "$STAGING"

if [[ "$SIGNING_IDENTITY" != "-" ]]; then
  requirement="$(codesign -d -r- "$STAGING" 2>&1)"
  if [[ "$requirement" == *"cdhash"* ]]; then
    echo "Refusing to install an app with an unstable cdhash requirement." >&2
    exit 1
  fi
fi

pkill -x "Window Layout" 2>/dev/null || true
rm -rf "$APP_DIR"
mkdir -p "$(dirname "$APP_DIR")"
ditto "$STAGING" "$APP_DIR"

LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
if [[ "$INSTALL_HOME" == "$HOME" && -x "$LSREGISTER" ]]; then
  "$LSREGISTER" -f "$APP_DIR"
fi

if [[ ! -f "$APP_SUPPORT/layouts.json" ]]; then
  printf '{\n  "layouts": [],\n  "updatedAt": "",\n  "version": 2\n}\n' > "$APP_SUPPORT/layouts.json"
fi

echo "Installed CLI: $CLI_DIR/window-layout"
echo "Installed app: $APP_DIR"
echo "Config: $APP_SUPPORT/layouts.json"

if [[ "${1:-}" != "--no-launch" ]]; then
  open "$APP_DIR"
fi
