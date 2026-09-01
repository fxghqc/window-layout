#!/usr/bin/env bash
set -euo pipefail

APP_SUPPORT="$HOME/Library/Application Support/window-layout"
CLI_PATH="$HOME/.local/bin/window-layout"
APP_DIR="$HOME/Applications/Window Layout.app"

pkill -x "Window Layout" 2>/dev/null || true
rm -f "$CLI_PATH"
rm -rf "$APP_DIR"

if [[ "${1:-}" == "--purge" ]]; then
  rm -rf "$APP_SUPPORT"
  echo "Removed application, CLI, and saved layouts."
else
  echo "Removed application and CLI. Saved layouts remain at: $APP_SUPPORT"
fi
