# Bug 014: Back navigation to a freshly-edited new note shows empty editor

## Status: FIXED — verified 2026-05-03

## Description

When the user creates a new note, types content into it, opens a different note, then taps back to return to the new note, the editor shows the new note as empty. The sidebar correctly shows the new note's derived title and highlights it as selected — only the editor body is wrong.

Expected: editor shows the content typed in step 2.

## Steps to Reproduce

1. Open app on iPad (regular size class) or iPhone — both paths use `splitNoteHistory` / native NavigationStack.
2. Tap the "create note" button to create an empty new note. Editor opens.
3. Type some text (e.g. "Hello world").
4. Tap a different existing note in the sidebar.
5. Tap the back button (history back / native back).
6. **Observation:** editor body is empty even though sidebar shows the new title and the file on disk has the typed content.

## Root Cause

`VaultWorkspaceView.updateSelectedNote(_:)` (in `Noto/Views/NoteListView.swift`) had a leading guard that returned early when the incoming updated note no longer matched `selectedNote`. The split-view editor calls `onNoteUpdated(session.note)` from inside `.onDisappear`, *after* `selectNote(B)` has already moved `selectedNote` to a different note. The disappear-time update carries the freshly-renamed fileURL of the new note (`Hello.md` instead of `Untitled.md`), but the guard rejected it, so neither `splitNoteHistory` nor `splitNoteStackNavigation` had their entries refreshed. On back, the history entry still held the stale `Untitled.md` URL — the file no longer existed (renamed away), so `NoteEditorSession.loadNoteContent()` read an empty body and the editor rendered blank.

The compact iPhone path (`updateCompactHistory`) doesn't have this defect because it always replaces history entries unconditionally; only the iPad/macOS split path went through the guarded `updateSelectedNote`.

## Fix

Move history-entry refresh (`splitNoteHistory.replaceEntries(for:)` + iOS `splitNoteStackNavigation.replaceEntries(for:)`) above the guard so it always runs for any note ID present in history, regardless of whether the note is currently selected. The selection-update branch (which depends on `currentSplitStackEntry`) stays guarded.

## Success Criteria

### 1. Back navigation to a freshly-edited new note shows the latest content
- [x] Verified in unit test (existing `noteNavigationHistoryUpdatesRenamedNonCurrentEntries` covers the underlying data layer; all 5 `NoteNavigationHistoryTests` pass)
- [x] Verified in simulator (iPad Pro 13" iOS 26.2 — created note, typed "FixedHistoryBack", switched to Long Scrolling Note, tapped back → editor showed `# fixedhistoryBack`)

**Unit test:** `NEW` — `NotoTests/MarkdownNoteStoreTests.swift` → `noteNavigationHistoryReplacesEntriesForNonSelectedNoteUpdate` (covers the underlying invariant that `replaceEntries(for:)` updates older history entries even when a different note is currently visible).

**Simulator verification:**
1. Build and launch on an iPad simulator with a seeded vault.
2. Open the sidebar.
3. Tap the "New Note" button; type a unique heading (e.g. "Hello back-nav") quickly without waiting.
4. Within 800ms (before the rename debounce), tap a different note in the sidebar.
5. Wait for the second note to render, then tap the editor's history-back button (top-right chevron-left).
6. **Expected:** editor renders the new note's typed heading; the file on disk uses the renamed filename derived from the heading.

### 2. Renaming the visible note still updates selectedNote and current history entry
- [x] Verified by inspection — fix is purely additive (moves the unconditional history-replace before the guard); the guarded selection-update path is unchanged. Existing `noteNavigationHistoryReplacesVisibleVisitWhenNoteIsRenamed` covers the data layer.

**Simulator verification:**
1. Build and launch.
2. Open an existing note, edit its first line so the title changes.
3. Wait ~1 second for autosave + rename.
4. **Expected:** sidebar reflects the new title; editor still shows the renamed note's content; the breadcrumb/title at the top of the editor reflects the new filename.

## Investigation Log

### Attempt 1 — Reproduce in simulator
