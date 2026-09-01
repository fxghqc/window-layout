#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_SUPPORT="$HOME/Library/Application Support/window-layout"
CLI_DIR="$HOME/.local/bin"
APP_DIR="$HOME/Applications/Window Layout.app"
STAGING="$(mktemp -d)/Window Layout.app"

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

mkdir -p "$CLI_DIR" "$APP_SUPPORT" "$STAGING/Contents/MacOS"
install -m 755 "$BIN_DIR/window-layout" "$CLI_DIR/window-layout"
install -m 755 "$BIN_DIR/window-layout-menu" "$STAGING/Contents/MacOS/Window Layout"
install -m 644 "$ROOT/Resources/Info.plist" "$STAGING/Contents/Info.plist"

codesign --force --deep --sign - "$STAGING"

pkill -x "Window Layout" 2>/dev/null || true
rm -rf "$APP_DIR"
mkdir -p "$(dirname "$APP_DIR")"
ditto "$STAGING" "$APP_DIR"

if [[ ! -f "$APP_SUPPORT/layouts.json" ]]; then
  printf '{\n  "layouts": [],\n  "updatedAt": "",\n  "version": 2\n}\n' > "$APP_SUPPORT/layouts.json"
fi

echo "Installed CLI: $CLI_DIR/window-layout"
echo "Installed app: $APP_DIR"
echo "Config: $APP_SUPPORT/layouts.json"

if [[ "${1:-}" != "--no-launch" ]]; then
  open "$APP_DIR"
fi
