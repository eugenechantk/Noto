#!/bin/bash
# Seed a Noto vault on an iOS simulator with folders and sample notes.
# Usage: ./seed-vault.sh <simulator-udid>
#
# Creates Documents/Noto/ with:
#   - Projects/ (empty folder)
#   - Archive/ (empty folder)
#   - Meeting Notes.md (headings + paragraphs)
#   - Shopping List.md (bullets)
#   - Project Plan.md (todos)
#
# Also sets the UserDefaults key so the app skips the vault setup screen.

set -euo pipefail

UDID="${1:?Usage: $0 <simulator-udid>}"
BUNDLE_ID="com.eugenechan.Noto"

# Get the app's data container path
DATA_DIR=$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data 2>/dev/null || true)

if [ -z "$DATA_DIR" ]; then
    echo "Error: App not installed on simulator $UDID. Build and install first."
    exit 1
fi

VAULT_DIR="$DATA_DIR/Documents/Noto"
NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

echo "Seeding vault at: $VAULT_DIR"

# Clean and recreate
rm -rf "$VAULT_DIR"
mkdir -p "$VAULT_DIR/Projects"
mkdir -p "$VAULT_DIR/Archive"

# --- Meeting Notes ---
cat > "$VAULT_DIR/Meeting Notes.md" << 'NOTEEOF'
---
id: a1b2c3d4-e5f6-7890-abcd-000000000001
created: 2026-03-15T09:00:00Z
modified: 2026-03-15T09:00:00Z
---
# Meeting Notes

## Agenda

Discuss Q2 roadmap and resource allocation for the new mobile app project.

## Action Items

Follow up with the design team about the new landing page mockups.
Schedule a review meeting for next Thursday.
NOTEEOF

# --- Shopping List ---
cat > "$VAULT_DIR/Shopping List.md" << 'NOTEEOF'
---
id: a1b2c3d4-e5f6-7890-abcd-000000000002
created: 2026-03-15T10:00:00Z
modified: 2026-03-15T10:00:00Z
---
# Shopping List

- Fruits
- Vegetables
- Dairy

## Notes

Check the farmers market on Saturday for fresh produce.
NOTEEOF

# --- Project Plan ---
cat > "$VAULT_DIR/Project Plan.md" << 'NOTEEOF'
---
id: a1b2c3d4-e5f6-7890-abcd-000000000003
created: 2026-03-15T11:00:00Z
modified: 2026-03-15T11:00:00Z
---
# Project Plan

- [ ] Design wireframes
- [ ] Build prototype
- [ ] Write documentation

## Completed

- [x] Set up repository
- [x] Review requirements
NOTEEOF

# Set UserDefaults so the app uses local vault (skips setup screen)
xcrun simctl spawn "$UDID" defaults write "$BUNDLE_ID" vaultIsLocal -bool true

echo "Done. Vault seeded with 2 folders and 3 notes."
