# Bug 015: Search sheet beachballs on open and on scope toggle (macOS)

## Status: FIX DEPLOYED — awaiting user verification

## Description

On macOS, the search sheet shows the rainbow spinning beachball:
1. When opening the search sheet (⌘F or magnifying glass).
2. When toggling the scope picker between "Title + Content" and "Title".

Expected: opening the sheet and toggling scope should be instant — heavy work belongs off the main thread.

## Steps to Reproduce

1. Launch Noto on macOS with a non-trivial vault (≥ a few notes).
2. Press ⌘F to open the search sheet → cursor turns into rainbow beachball for ~1–3s before recents appear.
3. Type a query so results render.
4. Click the "Title" or "Title + Content" segment, or press ⌘1/⌘2.
5. Cursor turns into beachball again while results re-render.

## Root Cause

Heavy main-thread work in two places in `Noto/Views/NoteListView.swift`:

1. **`appResult(for:rootStore:)`** (line ~2373) — called for every search result on the main actor inside `scheduleSearch`. It calls `rootStore.note(atVaultRelativePath:)`, which goes to `NoteRepository.noteRecord(at:)` and **reads the entire markdown file** (`fileSystem.readString(from:)`) just to extract the title via `VaultMarkdown.displayTitle(for:content:)`. With up to 60 results, that's 60 full-file reads on the main thread for every search/scope-toggle.

2. **`loadRecentNotes()`** (line ~2149) — runs the file enumeration off main, but the post-await `compactMap` runs on the main actor and calls `rootStore.note(atVaultRelativePath:)` for each of the 10 most-recent entries → 10 full-file reads on the main thread on every sheet open.

The `SearchResult` already carries `noteID`, `fileURL`, `title`, `updatedAt` from the SQLite index — there is no need to re-read each file to construct a `MarkdownNote`/`MarkdownNoteStore` for the search row. For recents, the per-file read can move to the same detached task that does the directory enumeration.

## Investigation Log

### Attempt 1

**Hypothesis:** Main-thread file I/O during `appResult` and `loadRecentNotes`.
**Evidence:**
- `MarkdownNoteStore.note(atVaultRelativePath:)` calls `noteRepository.note(...)` → `noteRecord(at:)` → `fileSystem.readString(from: fileURL)` (full file).
- `scheduleSearch` maps `appResult` over up to 60 results on the main actor (line 2125).
- `loadRecentNotes` post-await `compactMap` runs on the main actor (line 2156) and calls `rootStore.note(...)` for each entry.
- `MarkdownNoteStore` is `@MainActor`, so the existing detached-task patterns can't move the lookups off main; the file reads themselves must be moved.
**Plan:** (1) Drop the `rootStore.note` lookup from `appResult` — construct `MarkdownNote`/`MarkdownNoteStore` directly from the search result. (2) For `loadRecentNotes`, perform `NoteRepository.note(atVaultRelativePath:)` in the detached task and pass back resolved `VaultNoteRecord`s; keep only the lightweight store construction on main.

## Fix

`Noto/Views/NoteListView.swift`:

- `appResult(for:rootStore:)` no longer calls `rootStore.note(atVaultRelativePath:)`. The `MarkdownNote` and `MarkdownNoteStore` are constructed directly from `SearchResult` fields (`noteID`, `fileURL`, `title`, `updatedAt`). Section results fall back to filename for the note title (the row already shows the section heading via `result.title`).
- `loadRecentNotes()` now performs the per-entry `NoteRepository.note(atVaultRelativePath:)` lookup inside the existing detached task, alongside `recentVaultNoteEntries`. Only the lightweight `MarkdownNoteStore`/`MarkdownNote` construction stays on the main actor. When a record is missing, the fallback uses `VaultDirectoryLoader.stableID(for:)` so the note id is path-stable.

Net effect: opening the sheet does at most one `FileManager.fileExists` per recent entry on main; toggling scope with results does at most one `FileManager.fileExists` per row on main. Both are O(microseconds), not O(file-read).

## Success Criteria

### 1. Opening the search sheet does not beachball
- [ ] Verified in simulator/app
**Verification:** Press ⌘F in Noto on macOS. Cursor stays normal. Recents render within ~100ms.

### 2. Toggling scope with an active query does not beachball
- [ ] Verified in simulator/app
**Verification:** With a query and ≥10 results, click "Title" then "Title + Content" (or press ⌘1/⌘2). Cursor stays normal between toggles. Result list updates within debounce delay.

### 3. Selecting a search result still opens the correct note
- [ ] Verified in simulator/app
**Verification:** Search, click a note row, confirm the editor opens the right file with correct title and content.

### 4. Selecting a recent note still opens the correct note
- [ ] Verified in simulator/app
**Verification:** Open search (no query), click a recent row, confirm the editor opens the right file with correct title and content.

### 5. Existing search/vault test suites still pass
- [x] `swift test` in `Packages/NotoSearch` — 40/41 pass; one pre-existing live-vault count assertion failure unrelated to this change.
- [x] `swift test` in `Packages/NotoVault` — 52/52 pass.

