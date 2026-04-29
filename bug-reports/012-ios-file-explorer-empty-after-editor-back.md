# Bug 012: iOS file explorer sometimes appears empty after returning from editor

## Status: FIX DEPLOYED

## Description

On iOS, returning from an editor screen to the file explorer can show an empty tree even though the vault or folder contains files.

## Steps to Reproduce

1. Open Noto on iOS with a non-empty vault.
2. Open a note from the file explorer.
3. Navigate back from the editor to the file explorer.
4. Sometimes the file explorer shows no items, despite the directory being non-empty.

## Root Cause

Compact iOS `NavigationStack` folder routes created `MarkdownNoteStore(autoload: false)` inline when constructing `FolderContentView`. When navigating back from an editor, SwiftUI could rebuild that explorer destination around a fresh empty store before the async directory load repopulated it. The underlying vault was still non-empty; the visible tree had lost its previously loaded store instance.

## Success Criteria

### 1. Returning from an iOS editor preserves the loaded file explorer store
- [x] Verified by build
- [ ] Verified in simulator

**Unit test:** Existing coverage for deferred navigation destination loading in `NotoTests/MarkdownNoteStoreTests.swift` confirms stores with `autoload: false` populate through `loadItemsInBackground()`. The fix is SwiftUI state ownership in `FolderContentView`, so compile coverage is the practical automated gate here.

**Simulator verification:**
1. Build and launch on an iPhone simulator with a seeded non-empty vault.
2. Open a note from the root file explorer.
3. Tap Back to return to the file explorer.
4. Repeat from a nested folder note.
5. **Expected:** the file explorer still shows its folders/notes and does not flash or settle into an empty tree.

## Investigation Log

### Attempt 1

**Hypothesis:** Compact iOS folder destinations can be rebuilt with a fresh `MarkdownNoteStore(autoload: false)` while navigating back from editor to explorer, temporarily replacing the loaded tree with an empty store.

**Changes:** `FolderContentView` now stores its passed `MarkdownNoteStore` in `@State`, preserving the loaded explorer store across SwiftUI destination recomputation.

**Result:** iPhone simulator build passed. Full simulator repro verification still pending because the bug is intermittent.
