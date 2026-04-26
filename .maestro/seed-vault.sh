#!/bin/bash
# Seed a Noto vault on an iOS simulator with folders and sample notes.
# Usage:
#   ./seed-vault.sh <simulator-udid> [--scale small|large]
#   ./seed-vault.sh <simulator-udid> --current-vault
#   ./seed-vault.sh <simulator-udid> --source-vault <path>
#
# Small scale creates Documents/Noto/ with:
#   - Projects/ (empty folder)
#   - Archive/ (empty folder)
#   - Captures/ (Reader/Readwise-style capture folder)
#   - Meeting Notes.md (headings + paragraphs)
#   - Shopping List.md (bullets)
#   - Project Plan.md (todos)
#   - Long Scrolling Note.md (long editor content for scrolling/glass checks)
#   - Captures/The State of Consumer AI - Usage.md (captured source note)
#   - Captures/The $120K Blueprint What 2 Years ofBuilding in Public Won't Teach You About Actually Making Money.md (long stress-test capture)
#
# Large scale creates a performance vault. Defaults can be overridden:
#   ROOT_NOTE_COUNT=2000 FOLDER_COUNT=12 NOTES_PER_FOLDER=1000 ./seed-vault.sh <udid> --scale large
#
# Also sets the UserDefaults key so the app skips the vault setup screen.

set -euo pipefail

usage() {
    cat <<USAGE
Usage:
  $0 <simulator-udid> [--scale small|large]
  $0 <simulator-udid> --current-vault
  $0 <simulator-udid> --source-vault <path>

Options:
  --scale small|large    Generate the built-in seed vault. Default: small.
  --current-vault        Copy Eugene's current iCloud Noto vault into the simulator.
  --source-vault <path>  Copy an arbitrary local Noto vault into the simulator.
  --help                 Show this help.
USAGE
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    usage
    exit 0
fi

UDID="${1:?Usage: $0 <simulator-udid> [--scale small|large]}"
SCALE="small"
MODE="generated"
SOURCE_VAULT=""
CURRENT_VAULT="/Users/eugenechan/Library/Mobile Documents/com~apple~CloudDocs/Noto"

shift
while [ "$#" -gt 0 ]; do
    case "$1" in
        --scale)
            SCALE="${2:?Error: --scale requires small or large.}"
            MODE="generated"
            shift 2
            ;;
        --current-vault)
            SOURCE_VAULT="$CURRENT_VAULT"
            MODE="source"
            shift
            ;;
        --source-vault)
            SOURCE_VAULT="${2:?Error: --source-vault requires a path.}"
            MODE="source"
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        small|large)
            SCALE="$1"
            MODE="generated"
            shift
            ;;
        *)
            echo "Error: unknown option '$1'."
            usage
            exit 1
            ;;
    esac
done

if [ "$SCALE" != "small" ] && [ "$SCALE" != "large" ]; then
    echo "Error: scale must be 'small' or 'large'."
    exit 1
fi

if [ "$MODE" = "source" ]; then
    if [ -z "$SOURCE_VAULT" ]; then
        echo "Error: source vault path is empty."
        exit 1
    fi
    if [ ! -d "$SOURCE_VAULT" ]; then
        echo "Error: source vault does not exist: $SOURCE_VAULT"
        exit 1
    fi
fi

BUNDLE_ID="com.eugenechan.Noto"

# Get the app's data container path
DATA_DIR=$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data 2>/dev/null || true)

if [ -z "$DATA_DIR" ]; then
    echo "Error: App not installed on simulator $UDID. Build and install first."
    exit 1
fi

VAULT_DIR="$DATA_DIR/Documents/Noto"
NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURES_DIR="$SCRIPT_DIR/fixtures"

echo "Seeding vault at: $VAULT_DIR"

# Clean and recreate
rm -rf "$VAULT_DIR"
mkdir -p "$VAULT_DIR"

write_note() {
    local path="$1"
    local id="$2"
    local title="$3"
    local body="$4"

    printf -- "---\nid: %s\ncreated: %s\nmodified: %s\n---\n# %s\n\n%s\n" \
        "$id" "$NOW" "$NOW" "$title" "$body" > "$path"
}

seed_small_vault() {
    mkdir -p "$VAULT_DIR/Projects"
    mkdir -p "$VAULT_DIR/Archive"
    mkdir -p "$VAULT_DIR/Captures"

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

    # --- Long Scrolling Note ---
    cat > "$VAULT_DIR/Long Scrolling Note.md" << 'NOTEEOF'
---
id: a1b2c3d4-e5f6-7890-abcd-000000000004
created: 2026-03-15T12:00:00Z
modified: 2026-03-15T12:00:00Z
---
# Long Scrolling Note

This note is intentionally long so simulator checks can validate editor scrolling, bottom toolbar glass, keyboard avoidance, and selection behavior near the lower edge of the viewport.

## Morning Review

The first section starts near the top of the document and should be visible without scrolling. Use it to compare how the editor header, breadcrumb, and first paragraph settle when the note opens.

- Confirm the first visible heading has enough top spacing.
- Confirm regular paragraphs use the expected body width.
- Confirm the bottom toolbar does not cover the insertion point.

## Draft Plan

This section provides a few medium-length paragraphs so wrapped text has to flow across several visual lines. The text should feel natural enough to inspect line height, paragraph spacing, and scroll momentum without relying on generated placeholder words.

Design work often needs a page that is long enough to reveal problems only visible after motion. A short note can make the chrome look correct while hiding issues with scroll indicators, translucent overlays, and content that lands underneath the home indicator.

When testing glass effects, scroll slowly and stop with text directly behind the toolbar. The toolbar should stay legible, the content should remain readable, and the bottom of the document should still be reachable without awkward extra dragging.

## Tasks

- [ ] Scroll from the top to the middle of the document.
- [ ] Place the caret on a line close to the bottom toolbar.
- [ ] Open the keyboard and confirm the focused line remains visible.
- [ ] Dismiss the keyboard and confirm the toolbar returns to its resting position.
- [ ] Select a wrapped paragraph and verify selection handles do not collide with the toolbar.

## Notes On Interaction

The editor should preserve a stable reading column while the surrounding chrome floats above the content. If the glass effect is too opaque, the toolbar will feel heavy. If it is too transparent, the icons can become hard to see over dense text.

The most useful test is to stop scrolling with a heading or paragraph behind the toolbar. That gives a quick read on material contrast, capsule shape, and whether the bottom safe-area inset is large enough.

## Wrapped List

- A longer bullet item that should wrap onto a second line, giving the editor a chance to show whether indentation remains stable when text continues below the first baseline.
- Another longer bullet item with enough text to test selection, hit testing, and the transition from the visible list marker into wrapped body text.
- A final long bullet item near the middle of the note, useful for checking that scroll position and layout recalculation remain smooth after editing.

## Reference Paragraphs

The paragraphs below intentionally repeat the same rhythm. They make the document tall enough to test repeated scrolling without needing thousands of generated files in the small seed vault.

Section one focuses on the top third of the editor. The content should move cleanly under the navigation chrome and should not jump when the breadcrumb title changes or the note finishes loading.

Section two focuses on the middle of the editor. The scroll view should maintain momentum, text should remain crisp behind translucent material, and tapping a paragraph should place the caret exactly where expected.

Section three focuses on the lower part of the editor. The toolbar should remain centered on the app surface while the content continues underneath with enough inset to keep the last lines reachable.

Section four adds more body text so the note has a meaningful tail. This makes it easier to test rapid flicks, slow drags, and small adjustments around the bottom safe area.

Section five is close to the end of the document. When the keyboard is visible, this paragraph should still be reachable and should not be trapped behind any accessory toolbar or glass surface.

## Closing

Use the final lines to verify that the document can scroll past the bottom toolbar and that the last paragraph is not hidden. The insertion point should remain visible here.

The bottom of this note should be easy to reach, easy to edit, and visually clear even when the app chrome is layered above the text.
NOTEEOF

    # --- Captured Article ---
    cat > "$VAULT_DIR/Captures/The State of Consumer AI - Usage.md" << 'NOTEEOF'
---
id: a1b2c3d4-e5f6-7890-abcd-000000000005
created: 2026-03-15T13:00:00Z
modified: 2026-03-15T13:00:00Z
updated: 2026-03-15T13:00:00Z
type: source
source_kind: "article"
capture_status: full
canonical_key: "reader:seed-consumer-ai-usage"
source_title: "The State of Consumer AI - Usage"
reader_document_id: "seed-consumer-ai-usage"
source_url: "https://example.com/consumer-ai-usage"
reader_url: "https://read.readwise.io/read/seed-consumer-ai-usage"
reader_location: "new"
readwise_url: "https://read.readwise.io/read/seed-consumer-ai-usage"
readwise_bookreview_url: "https://readwise.io/bookreview/seed-consumer-ai-usage"
author: "Noto Seed"
site_name: "example.com"
published: "2026-03-02"
word_count: 640
tags:
  - imported/reader
  - imported/readwise
  - "app-building"
---
# The State of Consumer AI - Usage

Source: [The State of Consumer AI - Usage](https://example.com/consumer-ai-usage)
Readwise: [Open in Reader](https://read.readwise.io/read/seed-consumer-ai-usage)
Captured: 2026-03-15T13:00:00Z

<!-- noto:highlights:start -->
> Consumer AI apps become useful daily tools when they combine repeated use, low friction, and a clear reason to return.

> The strongest products feel less like demos and more like a saved workflow that is waiting in the right place.
<!-- noto:highlights:end -->

<!-- noto:content:start -->
![](https://picsum.photos/seed/noto-capture/1200/800)
*Source: Seed fixture*

## Usage is concentrating

The consumer AI market is broad, but usage tends to concentrate around a few durable jobs: searching, writing, summarizing, studying, organizing, and creating media. A capture note should preserve the source context while still behaving like any other editable Markdown file.

Good capture fixtures need enough structure to exercise rendering and navigation. This note includes frontmatter, source links, highlights, an image reference, headings, wrapped paragraphs, and lists.

## Product patterns

- Fast return paths matter more than novelty after the first session.
- Links such as [related usage notes](https://example.com/related-usage-notes) should render as clickable titles when the caret is outside the link line.
- Imported highlights should stay readable without becoming visually louder than the original note body.

## Capture checks

- [ ] Open this file from the Captures folder.
- [ ] Confirm the Source and Readwise rows render link titles.
- [ ] Place the caret on a link line and confirm the Markdown source appears.
- [ ] Edit a highlight and confirm the blockquote styling remains muted.

<!-- noto:content:end -->
NOTEEOF

    # --- Long Stress-Test Capture ---
    cp \
        "$FIXTURES_DIR/Captures/The \$120K Blueprint What 2 Years ofBuilding in Public Won't Teach You About Actually Making Money.md" \
        "$VAULT_DIR/Captures/"

    echo "Done. Vault seeded with 3 folders and 6 notes."
}

seed_large_vault() {
    local root_note_count="${ROOT_NOTE_COUNT:-2000}"
    local folder_count="${FOLDER_COUNT:-12}"
    local notes_per_folder="${NOTES_PER_FOLDER:-1000}"
    local total_notes=$((root_note_count + folder_count * notes_per_folder))

    echo "Creating large performance vault:"
    echo "  root notes: $root_note_count"
    echo "  folders: $folder_count"
    echo "  notes per folder: $notes_per_folder"
    echo "  total notes: $total_notes"

    local i folder_index note_index folder_name folder_path note_path note_id title body

    for i in $(seq 1 "$root_note_count"); do
        note_path="$VAULT_DIR/Root Note $(printf '%05d' "$i").md"
        note_id="00000000-0000-4000-8000-$(printf '%012x' "$i")"
        title="Root Note $(printf '%05d' "$i")"
        body="Root-level performance note $i. This note is intentionally small so list performance is dominated by file count, not file size."
        write_note "$note_path" "$note_id" "$title" "$body"

        if [ $((i % 500)) -eq 0 ]; then
            echo "  wrote $i / $root_note_count root notes"
        fi
    done

    for folder_index in $(seq 1 "$folder_count"); do
        folder_name="Folder $(printf '%02d' "$folder_index")"
        folder_path="$VAULT_DIR/$folder_name"
        mkdir -p "$folder_path"

        for note_index in $(seq 1 "$notes_per_folder"); do
            note_path="$folder_path/$folder_name Note $(printf '%05d' "$note_index").md"
            note_id="00000000-$(printf '%04x' "$folder_index")-4000-8000-$(printf '%012x' "$note_index")"
            title="$folder_name Note $(printf '%05d' "$note_index")"
            body="Nested performance note $note_index in $folder_name. Used to validate folder and search responsiveness at large vault scale."
            write_note "$note_path" "$note_id" "$title" "$body"
        done

        echo "  wrote $notes_per_folder notes in $folder_name"
    done

    echo "Done. Vault seeded with $folder_count folders and $total_notes notes."
}

seed_from_source_vault() {
    echo "Copying source vault from: $SOURCE_VAULT"
    rsync -a \
        --inplace \
        --exclude ".DS_Store" \
        --exclude ".noto/search.sqlite*" \
        "$SOURCE_VAULT"/ \
        "$VAULT_DIR"/

    local note_count
    note_count=$(find "$VAULT_DIR" -type f -name "*.md" | wc -l | tr -d " ")
    echo "Done. Vault seeded from source with $note_count markdown notes."
}

case "$MODE" in
    generated)
        case "$SCALE" in
            small)
                seed_small_vault
                ;;
            large)
                seed_large_vault
                ;;
        esac
        ;;
    source)
        seed_from_source_vault
        ;;
esac

# Set UserDefaults so the app uses local vault (skips setup screen)
xcrun simctl spawn "$UDID" defaults write "$BUNDLE_ID" vaultIsLocal -bool true
xcrun simctl spawn "$UDID" defaults delete "$BUNDLE_ID" lastOpenedNoteURL >/dev/null 2>&1 || true
