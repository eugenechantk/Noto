# Phase 5 Follow-Up: Intent-Emitter Surfaces

Date: 2026-04-27

## Current Verdict

Phase 5 follow-up is implemented.

Completed:

- `VaultWorkspaceView` owns global search/settings presentation, compact routing, split selection, and split note history.
- `VaultWorkspaceView` handles `VaultWorkspaceIntent` and translates intents into navigation or vault mutations.
- `NotoSplitView` receives sidebar/detail content and stays a layout/search-presentation shell.
- `FolderContentView` emits workspace intents instead of owning `NavigationPath` or mutating the store.
- `NotoSidebarView` emits workspace intents instead of mutating selected note state or creating/deleting/moving notes directly.
- `OwnershipDependencyTests` now enforce these boundaries for the split view, shared sidebar, and compact folder list.

## Original Phase 5 Bar

Phase 5 acceptance criteria said:

- `NoteListView`, `NotoSidebarView`, `FolderContentView`, and search result surfaces render data and emit workspace intents.
- Embedded workspace routing decisions are removed from those views.
- Platform shell logic lives in `VaultWorkspaceView`, not duplicated inside row/list components.
- List/sidebar components can be tested with supplied data and captured intents.

The current code does not meet that bar yet.

## Resolved Ownership Problems

### 1. `NotoSplitView` Still Owns Workspace Routing

Former responsibilities inside `NotoSplitView`:

- split selection bindings: `selectedNote`, `selectedNoteStore`, `selectedIsNew`
- note history and back/forward
- iPad native stack sync
- search result routing
- document-link routing
- root note creation
- editor detail construction

Implemented target:

- `VaultWorkspaceView` owns selected route/history.
- `NotoSplitView` receives:
  - sidebar content view
  - detail/editor view
  - column visibility intent callbacks
  - search presentation binding or intent
- `NotoSplitView` becomes a platform layout shell, not a route owner.

### 2. `NotoSidebarView` Still Mutates Workspace State

Former direct mutations:

- sets `selectedNote`, `selectedNoteStore`, `selectedIsNew`
- toggles `isSearchPresented`
- clears selection on delete
- creates notes/folders through `MarkdownNoteStore`
- deletes notes/folders through `MarkdownNoteStore`
- moves dropped notes directly

Implemented target:

- Replace selection/store bindings with read-only selected note identity/path.
- Replace mutations with intents:
  - `openSidebarNote(noteID/fileURL)`
  - `toggleSidebarFolder(folderURL)`
  - `createNote(parentURL)`
  - `createFolder(parentURL, name)`
  - `deleteSidebarItem(item)`
  - `moveNote(sourceURL, destinationFolderURL)`
  - `dismissSearch`
  - `toggleSearch`
- Keep local-only UI state in sidebar:
  - expanded folders
  - row loading
  - drag hover
  - new-folder alert text

### 3. `FolderContentView` Still Mutates Compact Navigation

Former direct routing:

- owns `@Binding var path: NavigationPath`
- appends folder routes
- appends note routes when no `onOpenNote` callback exists
- creates/deletes notes/folders through `MarkdownNoteStore`

Implemented target:

- Remove `NavigationPath` from `FolderContentView`.
- Make it emit intents:
  - `openFolder(folder)`
  - `openNote(note, store, isNew)`
  - `createNote(store)`
  - `createFolder(store, name)`
  - `deleteItems(store, offsets)`
  - `openToday`
  - `openSettings`
- `VaultWorkspaceView` converts those intents into `NavigationPath` updates or controller calls.

### 4. Search Result Surfaces Still Know Too Much About Routing Shape

Former:

- `NoteSearchSheet` emits `NoteSearchResult`, which includes `store` and `note`.
- Parent callers route differently by platform, but `NotoSplitView` still handles split search result selection.

Implemented target:

- Keep `NoteSearchSheet` mostly as-is for now, but treat result selection as a workspace intent:
  - `openSearchResult(result)`
- `VaultWorkspaceView` owns how that maps to compact stack vs split selection.

## Follow-Up Implementation

### Step 1: Introduce Workspace Intent Types

Status: done.

Add app-target types, probably near `VaultWorkspaceView` first:

```text
enum VaultWorkspaceIntent {
  case openNote(MarkdownNote, store: MarkdownNoteStore, isNew: Bool)
  case openFolder(NotoFolder, parentStore: MarkdownNoteStore)
  case openFolderURL(URL, name: String, vaultRootURL: URL)
  case openToday
  case openSearch
  case closeSearch
  case openSettings
  case createNote(in: MarkdownNoteStore)
  case createFolder(named: String, in: MarkdownNoteStore)
  case deleteItem(DirectoryItem, in: MarkdownNoteStore)
  case moveNote(MarkdownNote, from: MarkdownNoteStore, to: URL)
  case openDocumentLink(String)
  case updateSelectedNote(MarkdownNote)
  case clearSelection
}
```

Keep this internal and pragmatic. It does not need to be perfect upfront.

### Step 2: Add Workspace Intent Handler

Status: done.

`VaultWorkspaceView` gets a single method:

```text
handleWorkspaceIntent(_ intent)
```

This method should call `VaultController` or existing compatibility store methods, then update:

- compact `NavigationPath`
- split selection state
- history
- search/settings presentation
- externally deleting note state
- last-opened note persistence

### Step 3: Convert `FolderContentView`

Status: done.

Do this first because it is smaller than sidebar/split.

Changes:

- Remove `@Binding var path`.
- Remove direct `path.append`.
- Replace create/delete/open behavior with intent callbacks.
- Keep loading/empty UI and new-folder alert local.

Tests:

- Add a lightweight `FolderContentIntentTests` around a non-UI reducer/helper if practical.
- At minimum rerun workspace baseline and `NoteListViewTests`.

### Step 4: Convert `NotoSidebarView`

Status: done.

Changes:

- Replace selected note/store bindings with:
  - `selectedNoteFileURL: URL?`
  - `onIntent: (VaultWorkspaceIntent) -> Void`
- Keep expansion/search text/drop-hover local.
- Move actual create/delete/move decisions to `VaultWorkspaceView` or `VaultController`.

Important:

- macOS drag/drop should emit `moveNote(sourceURL, destinationFolderURL)`.
- Sidebar should reload its tree after workspace confirms the mutation, or via a passed reload token.

Tests:

- Add a small `SidebarIntentTests` if intent mapping is extracted.
- Rerun sidebar tree package tests and app workspace baseline.

### Step 5: Shrink `NotoSplitView`

Status: done.

Changes:

- Remove selected note/store bindings from `NotoSplitView`.
- Pass in sidebar and detail content from `VaultWorkspaceView`, or pass only selected route and intent callback.
- Move split note history and search result selection to `VaultWorkspaceView`.
- Keep only platform layout state in `NotoSplitView`:
  - column visibility
  - macOS window command target
  - split layout presentation

Acceptance:

- `NotoSplitView` no longer creates `NoteEditorScreen`.
- It no longer calls `store.createNote()`.
- It no longer resolves document links.

### Step 6: Add Enforcement Checks

Status: done.

Extend `OwnershipDependencyTests` after the conversion:

- `FolderContentView` should not reference `NavigationPath`.
- `NotoSidebarView` should not bind `selectedNoteStore`.
- `NotoSplitView` should not instantiate `NoteEditorScreen`.
- Views should not instantiate `MarkdownNoteStore` except inside `VaultWorkspaceView` compatibility routing.

## Verification Plan

Run after each step:

- `flowdeck test --only OwnershipRearchitecturePhase0BaselineTests/workspaceNavigationBaseline() --json -S "Noto-OwnershipRearch-Phase0"`
- `flowdeck test --only NoteListViewTests --json -S "Noto-OwnershipRearch-Phase0"`
- `flowdeck test --only OwnershipDependencyTests --json -S "Noto-OwnershipRearch-Phase0"`

Run after the full Phase 5 completion:

- `flowdeck test --only VaultControllerTests --json -S "Noto-OwnershipRearch-Phase0"`
- `flowdeck test --only NoteEditorSessionTests --json -S "Noto-OwnershipRearch-Phase0"`
- all Phase 0 baseline tests individually if suite-level filters hang
- focused iPhone/iPad/macOS UI smoke for:
  - root note open
  - nested folder open
  - search result open
  - document link open
  - create/delete selected note
  - sidebar drag/drop move on macOS

## Recommended Scope Decision

Do not try to complete this as one large patch.

Recommended order:

1. `FolderContentView` intent conversion.
2. `NotoSidebarView` intent conversion.
3. `NotoSplitView` shrink.
4. enforcement tests.

This keeps each change reviewable and gives tests a chance to catch routing regressions before the split-view layer is changed.
