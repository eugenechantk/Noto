# Bug 017: iPad sidebar spinner flashes every ~1s; sidebar scroll jank; editor scroll lag

## Status: FIX DEPLOYED — pending iCloud verification on device

## Description

On iPad with an iCloud-backed vault:

- Opening the sidebar shows a loading spinner.
- The spinner re-appears periodically (~every 1 second) even when the user is idle.
- Scrolling the sidebar list feels janky/laggy.

This does not happen on iPhone (different navigation surface) and does not happen on macOS in Eugene's setup.

## Steps to Reproduce

1. iPad with iCloud-backed vault (Eugene's setup).
2. Open the app.
3. Open the sidebar from a folder that contains many notes (e.g. `Captures` with ~700 items).
4. Observe: spinner overlay appears each time the sidebar's file watcher debounce tick fires (~500–1000ms cadence under iCloud sync).

## Root Cause

`DirectoryContentListView` (Noto/Views/NoteListView.swift:1088–1099) unconditionally calls `store.loadItemsInBackground()` whenever `fileWatcher.changeCount` ticks. Each call sets `isLoadingItems = true` (MarkdownNoteStore.swift:266), which the overlay (NoteListView.swift:1101–1113) renders as a `ProgressView()` over the entire list — even though the list already has items loaded.

Two problems compound:

1. **The overlay condition does not distinguish initial load from refresh.** It shows the spinner whenever `isLoadingItems == true`, regardless of whether the list currently has visible items. On iPad under active iCloud sync the file watcher fires repeatedly, so the spinner flashes regularly.
2. **The change handler does not filter by `lastChangedFileURL`.** Every file watcher tick — regardless of whether the changed file is in this directory — triggers a full reload of this store. `NoteSyncCenter` events (lines 1094–1099) already filter by `directoryURL`; the file watcher path does not. Each reload reassigns the entire `items` array, which contributes to the sidebar scroll jank because SwiftUI re-diffs the List on each tick.

Why macOS appears unaffected: macOS users typically have a less actively-syncing vault location (or `NSFileCoordinator` behaves differently for non-iCloud roots), so `changeCount` doesn't tick as frequently. The code path is identical — the bug is latent on macOS but exposed on iPad iCloud.

## Fix

Three changes:

1. `Noto/Views/NoteListView.swift` — only render the loading spinner when items are still empty (initial load). When items are already present, let the silent in-place refresh complete without flashing the overlay.
2. `Noto/Views/NoteListView.swift` — filter `fileWatcher.changeCount` ticks by `lastChangedFileURL` — only reload when the changed URL is in this store's directory, mirroring the `NoteSyncCenter` filter.
3. `Noto/Editor/TextKit2EditorView.swift` — throttle the `onContentOffsetYChange` callback to ~5 Hz (200 ms) for both iOS and macOS scroll handlers. The callback writes to `@SceneStorage` (`NoteEditorScreen.persistEditorContentOffsetY`), which invalidates the entire SwiftUI editor view on every call; firing it at 60 Hz during a scroll cascade is the dominant cause of editor scroll lag on iPad and macOS. On iOS, also flush on `scrollViewDidEndDragging` / `scrollViewDidEndDecelerating` so the final position is always persisted.

## Success Criteria

### 1. Sidebar with existing items does not flash a spinner on subsequent file watcher ticks
- [ ] Verified in unit test
- [ ] Verified in simulator

**Unit test:** EXISTING — covered indirectly by overlay-rendering logic; no new test required since the change is a single conditional.

**Simulator verification:**
1. Seed vault, build to iPad sim, open sidebar.
2. Externally modify a `.md` file (e.g. `touch` it via host shell) repeatedly.
3. **Expected:** the spinner overlay does not appear during these refresh ticks; items remain visible.

### 2. Initial load (empty store) still shows the spinner
- [ ] Verified in simulator

**Simulator verification:**
1. Open the sidebar for the first time after launch.
2. **Expected:** spinner shown briefly while items load, then replaced by item list.

### 3. File watcher ticks for files outside this directory do not trigger a reload
- [ ] Code-verified

**Verification:** Reading the modified `.onChange(of: fileWatcher?.changeCount)` block, confirm it guards on `lastChangedFileURL` parent directory matching `store.directoryURL`.
