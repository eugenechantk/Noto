#!/usr/bin/env bash
set -euo pipefail

SCHEME="${1:-Noto-macOS}"
DESTINATION="${2:-My Mac}"
APP_NAME="${3:-Noto}"
TARGET_APP="/Applications/${APP_NAME}.app"

build_log="$(mktemp)"
trap 'rm -f "$build_log"' EXIT

echo "Building ${APP_NAME} with FlowDeck..."
flowdeck build -s "$SCHEME" -D "$DESTINATION" --json | tee "$build_log" >/dev/null

derived_data_path="$(
  jq -r 'select(.type == "configuration") | .data.derivedDataPath // empty' "$build_log" | tail -n 1
)"

if [[ -z "$derived_data_path" ]]; then
  echo "Failed to resolve FlowDeck derived data path." >&2
  exit 1
fi

source_app="${derived_data_path}/Build/Products/Debug/${APP_NAME}.app"
if [[ ! -d "$source_app" ]]; then
  echo "Built app not found at ${source_app}" >&2
  exit 1
fi

echo "Stopping any running ${APP_NAME} process..."
osascript -e "tell application \"${APP_NAME}\" to quit" >/dev/null 2>&1 || true
pkill -x "$APP_NAME" >/dev/null 2>&1 || true
sleep 1

echo "Replacing ${TARGET_APP}..."
rm -rf "$TARGET_APP"
cp -R "$source_app" "$TARGET_APP"

if [[ ! -d "$TARGET_APP" ]]; then
  echo "Failed to install ${TARGET_APP}" >&2
  exit 1
fi

echo "Launching ${TARGET_APP}..."
open -na "$TARGET_APP"
sleep 1

registered_path="$(osascript -e "POSIX path of (path to application \"${APP_NAME}\")" 2>/dev/null || true)"
registered_path="${registered_path%/}"

if [[ -n "$registered_path" && "$registered_path" != "$TARGET_APP" ]]; then
  echo "Warning: LaunchServices resolves ${APP_NAME} to ${registered_path}, not ${TARGET_APP}" >&2
  exit 1
fi

echo "Installed and launched ${TARGET_APP}"
