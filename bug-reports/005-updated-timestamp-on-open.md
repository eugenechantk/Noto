# Bug 005: Updated timestamp changes when note is opened without editing

## Status: FIXED — verified 2026-03-28

## Description

The `updated` field in a note's YAML frontmatter is rewritten every time the note is opened and then closed, even if no content was changed.

## Steps to Reproduce

1. Note an existing note's `updated` timestamp by reading the file on disk
2. Tap the note to open it in the editor
3. Don't type anything — wait a few seconds
4. Tap back to close
5. Read the file on disk — `updated` timestamp has changed

## Root Cause

Two issues:

1. `saveContent` called `updateTimestamp` on every invocation regardless of whether body content changed
2. Even after fixing #1, `onDisappear` was writing stale in-memory content (with old frontmatter) back to disk, overwriting the debounced save's updated frontmatter

## Success Criteria

### 1. Opening and closing a note without editing does NOT change the `updated` timestamp
- [x] Verified in unit test
- [x] Verified in simulator

**Unit tests:**
- `NEW` — `NotoTests/MarkdownNoteStoreTests.swift` → `testSaveUnchangedContentDoesNotUpdateTimestamp`
- `NEW` — `NotoTests/MarkdownNoteStoreTests.swift` → `testMultipleSavesWithoutChanges`

**Simulator verification:**
1. Build and launch app on simulator
2. Read note's `.md` file on disk — record `updated:` timestamp
3. Tap the note to open it
4. Wait 3 seconds without typing
5. Tap back to close
6. Read the `.md` file on disk again
7. **Expected:** `updated` timestamp is identical to step 2

### 2. Editing a note and closing it DOES update the `updated` timestamp
- [x] Verified in unit test
- [x] Verified in simulator

**Unit test:** `NEW` — `NotoTests/MarkdownNoteStoreTests.swift` → `testSaveChangedContentUpdatesTimestamp`

**Simulator verification:**
1. Read note's `.md` file on disk — record `updated:` timestamp
2. Tap the note to open it
3. Tap into content area and type text (e.g. " E2E")
4. Wait 2 seconds for debounced save
5. Tap back to close
6. Read the `.md` file on disk
7. **Expected:** `updated` timestamp is newer than step 1, AND preserved after closing (not reverted)

### 3. The debounced auto-save (300ms) updates the timestamp while still in the editor
- [x] Verified in unit test (same code path as criterion 2)
- [x] Verified in simulator

**Unit test:** `EXISTING` — covered by criterion 2's test (same `saveContent` code path)

**Simulator verification:**
1. Read note's `.md` file on disk — record `updated:` timestamp
2. Tap the note to open it
3. Type some text
4. Wait 500ms (past the 300ms debounce) — do NOT navigate away
5. Read the `.md` file on disk while still in the editor
6. **Expected:** `updated` timestamp has already changed

### 4. Note list sort order is not affected for unedited notes
- [x] Verified in unit test
- [x] Verified in simulator

**Unit test:** `NEW` — `NotoTests/MarkdownNoteStoreTests.swift` → `testUnchangedSavePreservesModifiedDate`

**Simulator verification:**
1. Note the order of notes in the list
2. Tap a note that is NOT first in the list
3. Don't type anything — wait 3 seconds
4. Tap back
5. Screenshot the note list
6. **Expected:** List order unchanged — the note is still in its original position

### 5. `created` timestamp is never modified by any save
- [x] Verified in unit test

**Unit test:** `NEW` — `NotoTests/MarkdownNoteStoreTests.swift` → `testCreatedTimestampNeverChanges`

## Investigation Log

### Attempt 1

**Hypothesis:** `saveContent` unconditionally calls `updateTimestamp`.

**Changes:** Compare body content before/after; only call `updateTimestamp` if body differs.

**Result:** Unit tests pass. But E2E verification revealed a second bug: `onDisappear` writes stale in-memory content (with old frontmatter) back to disk, overwriting the debounced save's updated timestamp.

### Attempt 2

**Hypothesis:** Writing unchanged content back to disk overwrites the updated frontmatter from the debounced save.

**Changes:** Changed `saveContent` to return early without writing when body is unchanged (instead of writing the stale content).

**Result:** All 58 unit tests pass. All 4 simulator E2E criteria verified.

**Key insight:** The E2E simulator verification caught a bug that unit tests missed — the interaction between debounced save and `onDisappear` save only manifests in the real app flow.
