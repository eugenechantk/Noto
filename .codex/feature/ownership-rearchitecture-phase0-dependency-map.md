# Ownership Rearchitecture Phase 0 Dependency Map

This map freezes the current ownership and dependency shape before Phase 1 starts.

## Store And Vault Operations

Current app-facing store:

- `Noto/Storage/MarkdownNoteStore.swift`

Primary call sites:

- `Noto/NotoApp.swift`
  - creates the root `MarkdownNoteStore` for the configured vault.
  - passes store into the current workspace/list shell.
- `Noto/Views/NoteListView.swift`
  - owns large parts of workspace routing and creates child `MarkdownNoteStore` instances for folders.
  - creates `NoteEditorScreen`.
  - creates/searches notes and folders through `MarkdownNoteStore`.
- `Noto/Views/Shared/NotoSidebarView.swift`
  - opens, creates, moves, and deletes notes/folders through `MarkdownNoteStore`.
- `Noto/Views/Shared/NotoSplitView.swift`
  - owns split selection and creates store instances when opening search/history/document-link results.
- `Noto/Views/NoteEditorScreen.swift`
  - receives a `MarkdownNoteStore`.
  - creates `NoteEditorSession`.
  - deletes and moves the current note through the session/store.
- `Noto/Editor/NoteEditorSession.swift`
  - loads, saves, renames, moves, imports attachments, and reads conflict data through `MarkdownNoteStore`.

Current package support:

- `Packages/NotoVault/Sources/NotoVault/VaultDirectoryLoader.swift`
- `Packages/NotoVault/Sources/NotoVault/SidebarTreeLoader.swift`
- `Packages/NotoVault/Sources/NotoVault/NoteTitleResolver.swift`
- `Packages/NotoVault/Sources/NotoVault/Frontmatter.swift`
- `Packages/NotoVault/Sources/NotoVault/VaultListItem.swift`
- `Packages/NotoVault/Sources/NotoVault/VaultManager.swift`

Phase 3 migration destination:

- move filesystem, repository, daily note, attachment, and path-resolution mechanics into `NotoVault`.
- keep `MarkdownNoteStore` only as a temporary compatibility wrapper until call sites move to `VaultController`.

## File Coordination And Watchers

Current file primitives:

- `Noto/Storage/CoordinatedFileManager.swift`
  - coordinated read/write/data/prefix/delete/move/create directory.
  - iCloud download/readability helpers.
- `Noto/Storage/VaultFileWatcher.swift`
  - `NSFilePresenter`-backed external file watcher.

Primary call sites:

- `MarkdownNoteStore`
  - all note/folder create, save, rename, move, delete, daily note, and attachment writes.
- `NoteEditorSession`
  - content load, download/readability checks, and remote/external reloads.
- `TextKit2EditorView`
  - image loading/download checks.
- `NotoSidebarView` and `NotoSplitView`
  - a few current existence/read checks around sidebar/document-link behavior.

Phase 3 migration destination:

- package-level `VaultFileSystem` and `CoordinatedVaultFileSystem` in `NotoVault`.
- app still owns watcher lifecycle unless a later adapter is useful.

## Search Index

Current app-level coordinator:

- `Noto/SearchIndexRefreshCoordinator.swift`
  - single-flight vault refresh.
  - file refresh scheduling/debounce.
  - replace/remove file refresh.
  - posts `.notoSearchIndexDidChange`.

Primary call sites:

- `Noto/NotoApp.swift`
  - app startup, foreground activation, daily note prewarm refresh.
- `Noto/Storage/MarkdownNoteStore.swift`
  - create/save/rename/delete/move side effects.
- `Noto/Views/NoteListView.swift`
  - search sheet prepares/refreshes index and listens for index-change notifications.

Current package support:

- `Packages/NotoSearch/Sources/NotoSearch/MarkdownSearchIndexer.swift`
- `Packages/NotoSearch/Sources/NotoSearch/MarkdownSearchEngine.swift`
- `Packages/NotoSearch/Sources/NotoSearch/MarkdownSearchDocumentExtractor.swift`
- `Packages/NotoSearch/Sources/NotoSearch/SearchIndexStore.swift`
- `Packages/NotoSearch/Sources/NotoSearch/SearchTypes.swift`
- `Packages/NotoSearch/Sources/NotoSearch/SearchUtilities.swift`

Phase 2 migration destination:

- package actor `NotoSearch.SearchIndexCoordinator` owns refresh mechanics.
- app `SearchIndexController` owns lifecycle triggers and app notifications/state.

## Navigation And Workspace Ownership

Current workspace routing owner:

- `Noto/Views/NoteListView.swift`
  - compact iPhone `NavigationStack`.
  - search/settings presentation.
  - Today route.
  - restore last-opened note.
  - selected note/store state for regular-width layouts.
- `Noto/Views/Shared/NotoSplitView.swift`
  - regular-width split shell.
  - split selection.
  - note navigation history.
  - search overlay/sheet routing.
- `Noto/Views/Shared/NotoSidebarView.swift`
  - sidebar row rendering plus open/create/move/delete behavior.

Phase 4/5 migration destination:

- `VaultWorkspaceView` owns routing, search/settings presentation, Today, history, restore, and platform shells.
- list/sidebar/search/editor surfaces emit intents.
- `NoteListView` becomes a list surface instead of the workspace owner.

## Editor Ownership

Current note-scoped owner:

- `Noto/Editor/NoteEditorSession.swift`
  - one-note load/edit/autosave/rename/move/delete/conflict lifecycle.

Current UI/rendering owner:

- `Noto/Editor/TextKit2EditorView.swift`
  - TextKit rendering, editing transforms, page mention UI, document links, toolbar, selection/cursor behavior.

Phase 6 migration destination:

- `NoteEditorSession` keeps note-local state and delegates persistence to `VaultController`.
- `TextKit2EditorView` remains the native text editing/rendering layer.
- page mention UI remains editor-owned, but lookup can flow through `VaultController`.

## Phase 0 Baseline Tests Added

- `NotoTests/OwnershipRearchitecturePhase0BaselineTests.swift`
  - `workspaceNavigationBaseline`
  - `noteMutationBaseline`
  - `searchBaseline`
  - `editorInteractionBaseline`
  - `currentVaultSnapshotBaseline`

These are characterization tests for current behavior. They should remain green while later phases move ownership behind new abstractions.
