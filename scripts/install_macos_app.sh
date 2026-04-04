#!/usr/bin/env bash
set -euo pipefail

# Deterministic macOS install flow:
# 1. Build with FlowDeck and resolve the actual DerivedData product path.
# 2. Quit and kill the running app before replacing the bundle.
# 3. Remove /Applications/<App>.app instead of copying over it in place.
# 4. Re-register the fresh bundle with Launch Services and relaunch it explicitly.
# 5. Verify the running process binary is the /Applications bundle.
# 6. Write a visible build stamp into both:
#    - ~/Library/Application Support/Noto/installed-build.txt
#    - the app's UserDefaults domain
#    The app itself is sandboxed, so UserDefaults is the most reliable handoff.

SCHEME="${1:-Noto-macOS}"
DESTINATION="${2:-My Mac}"
APP_NAME="${3:-Noto}"
TARGET_APP="/Applications/${APP_NAME}.app"
STAMP_DIR="${HOME}/Library/Application Support/Noto"
STAMP_FILE="${STAMP_DIR}/installed-build.txt"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
BUNDLE_ID="com.eugenechan.Noto"

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

build_sha="$(git -C "$(pwd)" rev-parse --short HEAD)"
dirty_suffix=""
if ! git -C "$(pwd)" diff --quiet || ! git -C "$(pwd)" diff --cached --quiet; then
  dirty_suffix="-dirty"
fi
build_stamp="${build_sha}${dirty_suffix} $(date '+%Y-%m-%d %H:%M:%S')"

echo "Stopping any running ${APP_NAME} process..."
osascript -e "tell application \"${APP_NAME}\" to quit" >/dev/null 2>&1 || true
pkill -x "$APP_NAME" >/dev/null 2>&1 || true
sleep 1

mkdir -p "$STAMP_DIR"
printf '%s\n' "$build_stamp" > "$STAMP_FILE"
defaults write "$BUNDLE_ID" InstalledBuildStamp "$build_stamp" >/dev/null 2>&1 || true

echo "Replacing ${TARGET_APP}..."
rm -rf "$TARGET_APP"
cp -R "$source_app" "$TARGET_APP"

if [[ ! -d "$TARGET_APP" ]]; then
  echo "Failed to install ${TARGET_APP}" >&2
  exit 1
fi

touch "$TARGET_APP"

if [[ -x "$LSREGISTER" ]]; then
  "$LSREGISTER" -f "$TARGET_APP" >/dev/null 2>&1 || true
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

running_pid="$(pgrep -x "$APP_NAME" | tail -n 1 || true)"
if [[ -n "$running_pid" ]]; then
  running_binary="$(lsof -p "$running_pid" 2>/dev/null | awk '/\/Contents\/MacOS\// { print $9; exit }')"
  if [[ -n "$running_binary" && "$running_binary" != "${TARGET_APP}/Contents/MacOS/${APP_NAME}" ]]; then
    echo "Warning: Running process binary is ${running_binary}, not ${TARGET_APP}/Contents/MacOS/${APP_NAME}" >&2
    exit 1
  fi
fi

echo "Installed and launched ${TARGET_APP}"
echo "Build stamp: ${build_stamp}"
