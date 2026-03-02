#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PACKAGES=(
  NotoModels
  NotoCore
  NotoDirtyTracker
  NotoFTS5
  NotoEmbedding
  NotoTodayNotes
  NotoSearch
  NotoHNSW
)

for pkg in "${PACKAGES[@]}"; do
  echo "===== ${pkg} ====="
  (
    cd "$ROOT_DIR/Packages/$pkg"
    swift test
  )
done

echo "All package tests passed."
