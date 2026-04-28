# Simplified Architecture

## Goal

Reduce the mental model to a small number of durable ownership layers.

Target rule:

```text
Workspace routes.
Session edits.
VaultController persists.
TextKit renders text.
```

## Proposed Layers

```text
MainAppView
  -> VaultWorkspaceView
      owns navigation, search, settings, Today, sidebar/list/editor placement

NoteEditorScreen
  -> NoteEditorSession
      owns one open note's load/edit/autosave/rename/conflict lifecycle

VaultController
  -> NotoVault / NotoSearch / NotoReadwiseSync
      owns vault file operations, search, daily notes, watchers, sync integration

TextKit2EditorView
  owns native text editing, markdown rendering, cursor/selection behavior, editor chrome tied to text input
```

## What Gets Simpler

Current ownership is scattered across:

- `NoteListView`
- `NotoSplitView`
- `NotoSidebarView`
- `FolderContentView`
- `MarkdownNoteStore`
- `SearchIndexRefreshCoordinator`
- `VaultFileWatcher`
- `NoteEditorSession`
- `NoteEditorScreen`
- `EditorContentView`
- `TextKit2EditorView`

The simplified model keeps components, but makes ownership obvious:

- `VaultWorkspaceView` owns workspace navigation.
- `NoteListView` and sidebar render data and emit intents.
- `NoteEditorSession` owns one note's editor lifecycle.
- `VaultController` is the only app-facing interface for vault operations.
- Package services own non-UI mechanics.

## Simplified Note Open Lifecycle

```text
User taps note
  -> NoteListView emits openNote intent
  -> VaultWorkspaceView receives intent and updates route/selection
  -> NoteEditorScreen appears
  -> NoteEditorSession asks VaultController to load content
  -> TextKit2EditorView renders bound text
```

## Simplified Save Lifecycle

```text
User edits text
  -> TextKit2EditorView updates bound text
  -> NoteEditorSession tracks pending edits and debounce timers
  -> NoteEditorSession asks VaultController to save
  -> VaultController writes through NotoVault services
  -> VaultController updates search index and publishes app-facing changes
```

## Edit/Save Simplification

Current save flow exposes too many implementation details to the editor path:

```text
TextKit2EditorView
  -> TextKit2EditorCoordinator
  -> NoteEditorSession
  -> MarkdownNoteStore
  -> CoordinatedFileManager
  -> SearchIndexRefreshCoordinator
  -> NoteSyncCenter
```

Target mental model:

```text
TextKit2EditorView
  -> NoteEditorSession
  -> VaultController
```

`NoteEditorSession` should own only editor-local state:

- current content
- latest editor text
- last persisted text
- pending local edits
- autosave and rename debounce timers
- conflict/download/delete state

`VaultController` should hide persistence side effects:

- write file through `NotoVault`
- update note metadata
- rename if needed
- refresh/search-index side effects
- publish same-process save events

The behavior stays the same, but the editor only asks for intent-level operations such as `loadNote`, `saveNote`, and `renameIfNeeded`.

## Boundaries

`VaultWorkspaceView` should not know how files are written.

`NoteListView` should not create editor screens.

`NoteEditorSession` should not list folders or own vault-wide behavior.

`VaultController` should not own SwiftUI navigation or editor cursor state.

`NotoVault` should not import SwiftUI or own app lifecycle.

## Recommendation

Do not collapse everything into fewer files. Simplify by moving responsibilities to the right owners:

1. Introduce `VaultWorkspaceView`.
2. Introduce `VaultController`.
3. Move non-UI file/search mechanics into packages.
4. Make list/sidebar views intent emitters.
5. Keep `NoteEditorSession` focused on one note.

The goal is not fewer components. The goal is fewer ownership questions.
