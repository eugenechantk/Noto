# Bug 016: macOS sidebar becomes empty after editor restores a note in a subfolder

## Status: FIXED — verified 2026-05-12

## Description

On macOS launch:

- Vault root files briefly appear in the sidebar while the editor is still loading the previous note.
- Once the editor finishes loading a note that lives in a subfolder (e.g. `Ideas/Sleep tracking ∕ enhancement.md`), the sidebar header switches to that folder (e.g. "Ideas") but the body shows the "Empty — Secondary-click to create a note or folder" placeholder — even though the folder actually contains many notes.

## Steps to Reproduce

1. macOS app, vault is iCloud-backed.
2. Open a note that lives in a subfolder, then quit the app.
3. Relaunch Noto.
4. Observe: sidebar first shows vault root content, then switches to the subfolder header but the list is empty.

## Root Cause

`NotoSidebarView.expandToSelectedNote()` (added in the unmerged sidebar follow-selection work) was wired up to both `.onAppear` and `.onChange(of: selectedNote)`. On startup, both fire in quick succession:

1. `.onAppear` runs `expandToSelectedNote()` once. It creates a fresh `MarkdownNoteStore` for the target folder (`autoload: false`) and pushes it onto `folderStack`. `DirectoryContentListView.task(id: store.directoryURL.standardizedFileURL.path)` fires and calls `loadItemsInBackground()`. Items load — count = 14.
2. The restored selection sets `selectedNote`, which triggers `.onChange`. `expandToSelectedNote()` runs **again**, allocates a **new** `MarkdownNoteStore` for the **same** directory, and replaces the entry in `folderStack`.
3. `DirectoryContentListView` re-renders with the new store. But its `.task(id:)` keys on the directory path **string**, which hasn't changed — so the task does **not** re-fire, and the new store is never loaded.
4. The view observes the new store's `items` (`[]`) and `isLoadingItems` (`false`) → renders the "Empty" placeholder.

Verified via `DebugTrace`:

```
[03:39:03Z] sidebar expand component=Ideas exists=true   ← first call
[03:39:03Z] sidebar expand component=Ideas exists=true   ← second call (rebuilds with fresh store)
[03:39:03Z] store loaded dir=…/Ideas count=14            ← first store's load completes
                                                          ← second store never loads
```

## Fix

`Noto/Views/Shared/NotoSidebarView.swift` — short-circuit `expandToSelectedNote()` when `folderStack`'s components already match the target path. This avoids the unloaded-store replacement entirely.

```swift
if folderStack.map(\.title) == components {
    return
}
```

Also avoid the unnecessary `folderStack = []` write when already empty.

## Success Criteria

### 1. Restoring a note in a subfolder on launch shows that folder's items in the sidebar
- [x] Verified in simulator (macOS)

**Simulator verification:**
1. Set `lastOpenedNoteURL` to a note in a non-root folder.
2. Launch macOS app.
3. **Expected:** sidebar header reads the folder name and body lists the folder's notes with the restored note highlighted.

### 2. Restoring a note at the vault root keeps the sidebar at root
- [x] Code-verified — when `folderPath` is empty or `.`, `folderStack` is set to `[]` (no-op if already empty).

### 3. Switching selection between two notes in the same folder does not blank the sidebar
- [x] Code-verified — `folderStack.map(\.title) == components` short-circuit avoids rebuilding.

## Investigation Log

### Attempt 1 — visual reproduction
Launched the macOS app fresh. Sidebar header showed "Ideas" with body showing the "Empty" placeholder. Confirmed `ls` reports 14 notes in that folder.

### Attempt 2 — DebugTrace instrumentation
Added DebugTrace events in `expandToSelectedNote()` and `MarkdownNoteStore.loadItemsInBackground()`. Confirmed:
- `expandToSelectedNote()` ran twice for the same folder
- the directory loader successfully loaded 14 items
- yet the UI still showed empty

Concluded the second `expandToSelectedNote()` replaces the loaded store with an unloaded one and `.task(id:)` doesn't re-fire for the same path string.

### Attempt 3 — short-circuit fix
Compare `folderStack.map(\.title)` to the target components and bail out if equal. Visual verification after rebuild: sidebar correctly shows all 14 notes for Ideas, and an alternate vault path (Captures, 727 items) also renders correctly.
