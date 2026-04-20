# Shared Note List Architecture

## Problem

Noto currently has multiple code paths that decide what a note list row means and what title it displays:

- Compact iOS uses `FolderContentView` with `MarkdownNoteStore.loadItems()`.
- iPad/macOS split view uses `NotoSidebarView` with `SidebarTreeLoader`.
- The editor updates `NoteEditorSession.note`, but only the split-view path currently receives live selected-note updates.

This split creates product bugs. A new note starts as a UUID-backed file, then the user types a markdown title. One platform path may show the markdown title while another still shows the filename or stale title until a rename/reload occurs.

The core issue is not the editor. It is that note-list identity, title derivation, sorting, filtering, and update propagation are not shared.

## Goal

Create one shared list foundation for iPhone, iPad, and macOS so note/folder behavior is consistent everywhere.

The shared foundation should answer:

- What folders and notes exist in this directory/tree?
- What is the display title for each note?
- What is the stable identity for each row?
- How are rows sorted?
- How does a saved editor title update reach visible lists?
- How do create/delete operations update the list model?

Platform-specific views should only decide:

- Navigation container: `NavigationStack` vs `NavigationSplitView`.
- Toolbar placement.
- Context menu presentation.
- Selection behavior.

## Non-Goals

- Do not force iPhone, iPad, and macOS into one giant view.
- Do not remove platform-specific navigation shells.
- Do not redesign the editor.
- Do not introduce database/indexing infrastructure for this pass.
- Do not change file format or daily note location.

## Current State

### Compact iOS

`FolderContentView` renders `store.items`.

`MarkdownNoteStore.loadItems()` currently scans a directory and derives note title from the filename. This is fast, but it means `UUID.md` can appear as a UUID even when the note content contains `# My Title`.

### iPad/macOS Split Sidebar

`NotoSidebarView` renders rows from `SidebarTreeLoader`.

`SidebarTreeLoader` can now read note content and derive titles from markdown. It supports tree expansion and filtering, but it is separate from compact iOS.

### Editor

`NoteEditorScreen` owns a `NoteEditorSession`.

`NoteEditorSession` updates `session.note` as content changes. The split-view path can now observe this through `onNoteUpdated`, but compact iOS does not yet propagate that update back into the previous list screen.

## Proposed Architecture

Keep platform shells separate. Share the model, loader, title resolver, row rendering, and list actions.

```text
Markdown files on disk
    |
    v
NoteTitleResolver
    |
    v
VaultDirectoryLoader / VaultTreeLoader
    |
    v
VaultListItem / NoteSummary / FolderSummary
    |
    +--> iPhone Folder List
    +--> iPad Sidebar
    +--> macOS Sidebar
```

## Shared Types

### `NoteSummary`

Represents the list-facing projection of a note.

```swift
struct NoteSummary: Identifiable, Hashable, Sendable {
    let id: UUID
    let fileURL: URL
    let title: String
    let modifiedDate: Date
}
```

### `FolderSummary`

Represents the list-facing projection of a folder.

```swift
struct FolderSummary: Identifiable, Hashable, Sendable {
    let id: UUID
    let folderURL: URL
    let name: String
    let modifiedDate: Date
}
```

### `VaultListItem`

One item type for directory lists and tree rows.

```swift
enum VaultListItem: Identifiable, Hashable, Sendable {
    case folder(FolderSummary)
    case note(NoteSummary)
}
```

### `VaultTreeRow`

Only tree/sidebar views need depth and expansion state.

```swift
struct VaultTreeRow: Identifiable, Hashable, Sendable {
    let item: VaultListItem
    let depth: Int
    let isExpanded: Bool?
}
```

## Shared Services

### `NoteTitleResolver`

Single source of truth for display titles.

Rules:

- Read markdown content when available.
- Strip frontmatter.
- Use the first markdown heading/first line.
- Strip heading markers.
- If title is empty and filename is a UUID, show `Untitled`.
- If title is empty and filename is human-readable, use filename stem.

This is the primary fix for cross-platform rename/title drift.

### `VaultDirectoryLoader`

Loads one directory:

- returns `[VaultListItem]`
- folders first, alphabetically
- notes sorted by modified date descending
- notes use `NoteTitleResolver`

Compact iOS should use this instead of hand-maintaining a separate title derivation path in `MarkdownNoteStore.loadItems()`.

### `VaultTreeLoader`

Loads a depth-first tree for sidebars:

- returns `[VaultTreeRow]`
- preserves expanded/collapsed folder state
- uses `VaultDirectoryLoader` for each directory
- supports filtering while retaining ancestor folders

This can evolve from the current `SidebarTreeLoader`.

### `VaultListActions`

Shared file actions:

- create note in directory
- create folder in directory
- delete note/folder
- build `MarkdownNoteStore` for a selected note
- convert `NoteSummary` into `MarkdownNote`

The action results should return updated summaries/items so platform shells can update state immediately.

## Platform Views

### iPhone

`CompactFolderListView`

- Uses `NavigationStack`.
- Uses `VaultDirectoryLoader`.
- Pushes `NoteEditorScreen`.
- Passes `onNoteUpdated` so the visible list updates when returning from editor.
- Owns iOS toolbar placement.

### iPad/macOS

`SplitSidebarView`

- Uses `VaultTreeLoader`.
- Owns expansion state.
- Owns split-view selection state.
- Passes `onNoteUpdated` to `NoteEditorScreen`.
- macOS owns context menu presentation.
- iPad can reuse the same sidebar rows but keep iOS toolbar behavior.

## Rename/Title Update Flow

### Desired Behavior

When the user creates a note and types `# My Title`:

```text
Editor content changes
    |
    v
NoteEditorSession updates note title and saves content
    |
    v
onNoteUpdated(NoteSummary(title: "My Title"))
    |
    +--> compact iOS patches visible list row
    +--> iPad sidebar patches visible tree row
    +--> macOS sidebar patches visible tree row
```

When any list reloads from disk:

```text
VaultDirectoryLoader reads UUID.md
    |
    v
NoteTitleResolver reads "# My Title"
    |
    v
Every platform row displays "My Title"
```

This makes live updates and reloads consistent.

## Migration Plan

### Phase 1: Extract Shared Title Resolution

- Add `NoteTitleResolver` to `NotoVault`.
- Move current title derivation logic out of `SidebarTreeLoader`.
- Add tests for:
  - frontmatter stripping
  - markdown heading title
  - plain first-line title
  - UUID filename with empty content -> `Untitled`
  - human filename with unreadable/empty content -> filename stem

### Phase 2: Introduce Shared List Models

- Add `NoteSummary`, `FolderSummary`, and `VaultListItem`.
- Add conversion helpers between `MarkdownNote`/`NotoFolder` and summaries.
- Keep existing view code working while new loaders are introduced.

### Phase 3: Replace Directory Loading

- Add `VaultDirectoryLoader`.
- Update compact iOS `FolderContentView` to use shared `[VaultListItem]`.
- Update `MarkdownNoteStore.loadItems()` only if needed for compatibility, or deprecate it for list rendering.

### Phase 4: Replace Sidebar Tree Loading

- Rename/evolve `SidebarTreeLoader` into `VaultTreeLoader`.
- Have it compose `VaultDirectoryLoader`.
- Keep expansion/filter behavior covered by existing tests.

### Phase 5: Shared Rows and Actions

- Extract shared `VaultItemRow`, `NoteRow`, and `FolderRow` where practical.
- Extract shared create/delete helpers.
- Keep context menu and toolbar wrappers platform-specific.

### Phase 6: Cross-Platform Live Update

- Change editor update callback to return a shared note summary or enough data to patch one.
- Wire `onNoteUpdated` through compact iOS.
- Keep split sidebar update behavior.
- Add tests or UI smoke coverage for new-note title update on iPhone and macOS/iPad split.

## Test Strategy

### Unit Tests

Add/extend `NotoVault` tests for:

- `NoteTitleResolver`
- `VaultDirectoryLoader`
- `VaultTreeLoader`
- filtering with ancestor folders
- sorting
- empty title fallbacks

### App Tests

Add focused tests around editor/list state where possible:

- new note starts as `Untitled`
- typing `# My Title` updates editor session note title
- list model receives updated title

### Simulator/UI Verification

Use FlowDeck.

Required smoke checks:

- iPhone compact:
  - create note
  - type title
  - return to list
  - row shows typed title
- iPad regular:
  - create/select note in split view
  - type title
  - sidebar updates
- macOS:
  - create/select note
  - type title
  - sidebar updates
  - reload app
  - title persists from markdown content

## Acceptance Criteria

- One shared title resolver is used by all note-list paths.
- Compact iOS no longer derives visible note titles directly from filenames.
- iPad/macOS sidebars and iPhone lists display the same title for the same note file.
- New UUID-backed notes display `Untitled` until the user types a title.
- Typing a title in the editor updates visible list/sidebar rows without requiring app relaunch.
- Reloading from disk still displays markdown-derived titles before delayed filename rename.
- Platform-specific navigation and toolbar behavior remains intact.

## Open Decisions

- Should `MarkdownNoteStore.items` be deprecated for UI list rendering, or should it become a thin wrapper over `VaultDirectoryLoader`?
- Should live editor updates publish through `NoteSyncCenter`, a dedicated list-update notification, or direct callbacks only?
- Should title resolution read file contents synchronously for every list row, or should we add a small in-memory cache keyed by file URL + modified date?

## Recommendation

Start with `NoteTitleResolver` and `VaultDirectoryLoader` in `NotoVault`, then migrate compact iOS first. That closes the current cross-platform rename gap with the least UI churn.

After compact iOS and split sidebar both consume the shared loader, extract shared row/action components only where duplication remains obvious.

## Implementation Notes

### 2026-04-20 Pass

Implemented the shared foundation without replacing the platform navigation shells.

Added to `NotoVault`:

- `NoteTitleResolver`
- `NoteSummary`
- `FolderSummary`
- `VaultListItem`
- `VaultDirectoryLoader`
- `VaultTreeRow`

Updated `SidebarTreeLoader` so its compatibility API still returns `SidebarTreeNode`, but internally composes the shared directory loader and title resolver.

Updated `MarkdownNoteStore.loadItems()` to delegate to `VaultDirectoryLoader`, so compact iOS and split sidebars now share markdown-derived note titles.

Updated compact iOS `FolderContentView` to reload its directory model on:

- local editor save notifications from `NoteSyncCenter`
- file watcher changes
- view reappear

This closes the immediate cross-platform rename/title drift bug:

- a UUID-backed note with `# Cross Platform Title` displays as `Cross Platform Title` in compact iOS after returning to the list
- split sidebar rows use the same shared title resolver through `SidebarTreeLoader`

Remaining optional cleanup:

- Rename `SidebarTreeLoader` to `VaultTreeLoader` once call sites are ready for a breaking type rename.
- Extract shared SwiftUI row components if duplication remains after the data-layer migration settles.
- Decide whether direct callbacks or a dedicated list-update notification should replace the current compact iOS `NoteSyncCenter` reload hook.
