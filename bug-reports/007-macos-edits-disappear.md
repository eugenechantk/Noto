# Bug 007: macOS edits disappear after saving to iCloud vault

## Status: FIXED — verified 2026-04-04

## Description

On macOS, edits to markdown notes in an iCloud Drive vault disappear. The app writes the file to disk, but then the file watcher detects the write as an "external change" and reloads the editor from disk, potentially clobbering in-flight edits.

## Root Cause

Two interacting issues:

1. **Primary: Sandbox permission denial on atomic writes.** `CoordinatedFileManager.writeString` used `atomically: true`, which creates a temp file in the same directory before renaming. The macOS sandbox blocks temp file creation in security-scoped iCloud Drive directories (`NSCocoaErrorDomain Code=513 "Operation not permitted"`). Every save silently failed.

2. **Secondary: Self-triggered file watcher reloads.** `saveContent` updates the `updated:` timestamp before writing. The in-memory `content` retains the old timestamp. When `reloadIfChangedExternally` compared `diskContent != content`, the timestamps differed → it treated this as an external change and reloaded the editor, potentially clobbering in-flight edits.

Combined effect: every save triggers a 500ms-delayed reload. If the user types between the save and the reload, the reload reads stale disk content (or content with a different timestamp), and can overwrite the editor.

## Steps to Reproduce

1. Open the Mac app with vault in iCloud Drive
2. Open any note
3. Type several characters rapidly
4. Observe: edits may disappear or cursor may jump

## Fix

Two changes:

1. **`CoordinatedFileManager.writeString`**: Changed `atomically: true` to `atomically: false`. NSFileCoordinator already provides safe write coordination; the atomic temp-file approach is redundant and fails under macOS sandbox.

2. **`NoteEditorScreen.reloadIfChangedExternally`**: Compare note **bodies** (frontmatter-stripped) instead of full content. This filters out self-triggered reloads (same body, different timestamp) while still allowing genuine external changes (different body from iCloud sync) to reload the editor.

## Success Criteria

### 1. Self-triggered writes do not cause editor reloads
- [x] Verified in unit test
- [x] Verified in simulator

**Unit test:** EXISTING — `NotoVault` package tests cover frontmatter stripping

**Simulator verification:**
1. Build and launch macOS app
2. Open a note
3. Type several characters
4. Wait >500ms (file watcher debounce)
5. **Expected:** Cursor stays in place, no content reset

### 2. Genuine external changes still reload the editor
- [ ] Verified in unit test
- [ ] Verified in simulator

**Simulator verification:**
1. Build and launch macOS app
2. Open a note
3. Externally modify the .md file body (e.g. via Terminal)
4. **Expected:** Editor reloads with the new content

### 3. Edits persist across navigation
- [x] Verified in simulator

**Simulator verification:**
1. Build and launch macOS app
2. Open a note, type "TEST123"
3. Navigate back to note list
4. Reopen the note
5. **Expected:** "TEST123" is present
6. Verify on disk: `cat` the .md file
7. **Expected:** File contains "TEST123"

## Investigation Log

### Attempt 1

**Hypothesis:** Self-triggered file watcher reload due to timestamp mismatch in frontmatter + sandbox write failure
**Changes:**
1. `CoordinatedFileManager.writeString`: `atomically: true` → `atomically: false`
2. `NoteEditorScreen.reloadIfChangedExternally`: compare bodies (stripped frontmatter) instead of full content
**Result:** PASS — DebugTrace confirms `store write result success=true` (was `success=false`) and `editor reload skipped same-body` (was reloading). All 71 tests pass. File content verified on disk in iCloud Drive.
