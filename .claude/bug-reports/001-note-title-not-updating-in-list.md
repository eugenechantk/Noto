# Bug 001: Note title in list view does not update after editing

## Status: FIXED — verified in simulator via FlowDeck automation (2026-03-23)

## Description

When a note's title is edited in the editor, the note list view does not reflect the updated title. The list continues showing the old title (e.g., "Untitled") even after the user has typed a new title and navigated back. Reopening the app also shows the stale title.

## Steps to Reproduce

1. Open Noto, go to Notes list
2. Tap + → New Note (creates a note with `# ` heading, shows "Untitled")
3. Type a title after `# `, e.g., "My New Title"
4. Tap back to return to the list
5. **Expected:** List shows "My New Title"
6. **Actual:** List still shows "Untitled"

### Variant A: Paste content
1. Create a new note
2. Clear the title (leaving just `# `)
3. Paste a large block of text that includes a new title on the first line
4. Tap back
5. List still shows "Untitled"

### Variant B: App restart
1. Create a note and type a title
2. Navigate back to list
3. Force-quit and reopen the app
4. List shows "Untitled" instead of the typed title

## Root Cause Analysis

### Confirmed issues found so far:
1. **`shouldChangeTextIn` logic error (FIXED):** The delegate had `range.location == protectedEnd` checked inside `if range.location < protectedEnd`, which is an impossible condition. Text input was being silently blocked.

2. **Cursor landing in frontmatter (FIXED):** Tapping visually on the `#` character placed the cursor inside the hidden frontmatter zone. Added `textViewDidChangeSelection` to clamp cursor position.

3. **Still broken on device:** The above fixes resolved the issue in simulator but the bug persists on the physical iPhone. Possible causes:
   - The `textViewDidChangeSelection` clamping may cause a re-entrant loop on device
   - The debounced `saveContent` (300ms) may not fire before `onDisappear` on fast back-navigation
   - The `onDisappear` save may race with `loadItems()` called from `onAppear` on the list view
   - The `markdownContent()` method (which reverses bullet `•` → `-`) may produce content where `titleFrom()` returns wrong result
   - The `updateTimestamp()` in `saveContent` may corrupt the frontmatter, causing `titleFrom()` to fail to skip it on next load

## Files Involved

- `Noto/V2/Editor/MarkdownEditorView.swift` — `shouldChangeTextIn`, `textViewDidChangeSelection`, `textViewDidChange`
- `Noto/V2/Views/NoteEditorScreen.swift` — debounced save/rename, `onDisappear` flush
- `Noto/V2/Storage/MarkdownNoteStore.swift` — `saveContent()`, `loadItems()`, `titleFrom()`, `markdownContent()`
- `Noto/V2/Editor/MarkdownTextStorage.swift` — `markdownContent()` bullet reversal, frontmatter hiding

## Investigation Results

- [x] Add os_log to `saveContent()` — confirmed it fires correctly with correct title
- [x] Add os_log to `loadItems()` — confirmed it reads correct title from disk
- [x] Add os_log to `textViewDidChange` — confirmed content binding updates
- [x] `markdownContent()` correctly reverses bullet replacements
- [x] `updateTimestamp()` does not corrupt frontmatter
- [x] **ROOT CAUSE FOUND:** `onAppear` on list fires BEFORE `onDisappear` on editor

## Actual Root Cause

SwiftUI navigation timing: when the user taps back, the list's `onAppear` fires before the editor's `onDisappear`. The sequence:

1. User taps back
2. List `onAppear` → `loadItems()` re-reads file from disk (stale — debounced save hasn't fired)
3. Editor `onDisappear` → flushes save (writes correct content)
4. List now shows stale title from step 2

This explains why "tap in and back" fixes it — the second `onAppear` reads the now-correct file.

## Fix Applied

Removed `loadItems()` from `FolderContentView.onAppear`. The store's `@Published items` array is the single source of truth — it's updated by `saveContent()` in real-time. No need to re-read from disk on every appearance. Initial load happens in `init()`.

### Previous fixes (still applied):
1. Fixed `shouldChangeTextIn` impossible condition
2. Added `textViewDidChangeSelection` cursor clamping for frontmatter
