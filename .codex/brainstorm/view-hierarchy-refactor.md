# View Hierarchy Refactor

## Problem

`NoteListView` is misnamed. It currently acts as the vault workspace router:

- owns compact iPhone `NavigationStack`
- owns iPad/macOS split selection state
- creates `NoteEditorScreen`
- presents search and settings
- handles Today routing
- restores last-opened note
- tracks note navigation history

That makes the list and editor relationship harder to reason about. Conceptually, the note list and note editor should be sibling surfaces owned by a workspace shell.

## Proposed Shape

```text
NotoApp
  -> MainAppView
    -> VaultWorkspaceView
      -> compact iPhone NavigationStack
        -> NoteListView
        -> NoteEditorScreen
      -> iPad/macOS NavigationSplitView
        -> NoteListView / NotoSidebarView
        -> NoteEditorScreen
```

## Responsibilities

`MainAppView` should own app/vault lifecycle:

- root vault URL
- root store or future `VaultController`
- vault file watcher
- search-index refresh kickoff
- daily-note prewarm
- Readwise automatic sync
- scene phase handling

`VaultWorkspaceView` should own workspace navigation:

- compact iPhone route/path
- iPad/macOS split selection
- note history back/forward
- Today route
- search presentation
- settings presentation
- document-link routing
- restore last-opened note

`NoteListView` should become dumb list UI:

- render folders/notes
- show loading and empty states
- emit intents: open note, open folder, create note, delete item
- not create `NoteEditorScreen`
- not own global search/settings/editor routing

`NoteEditorScreen` should remain note-scoped:

- own `NoteEditorSession`
- load/edit/save/delete one note
- expose callbacks for delete, document links, Today, and navigation actions

## Search And Mention Placement

Global search should be workspace-owned:

```text
VaultWorkspaceView
  - owns isSearchPresented
  - presents NoteSearchSheet
  - receives selected result
  - routes to selected note
```

Reason: global search searches the vault and changes workspace navigation/selection.

Page mentions should remain editor-owned:

```text
NoteEditorScreen
  -> EditorContentView
    -> TextKit2EditorView
      -> page mention popover/sheet
```

Reason: mentions depend on the active editor cursor, selection range, keyboard behavior, and insertion into the current note. The data lookup can eventually go through `VaultController.pageMentions(...)`, but the mention UI belongs with the editor.

## Chrome Placement

Workspace bottom bar should be workspace-owned:

```text
VaultWorkspaceView
  -> compact NavigationStack / split shell
  -> bottom bar overlay
```

Reason: the bottom bar performs workspace actions: Today, global search, and new root note. It should emit workspace intents such as `onOpenToday`, `onOpenSearch`, and `onCreateRootNote`. It should not live inside `NoteListView`.

Keyboard toolbar should be editor-owned:

```text
NoteEditorScreen
  -> EditorContentView
    -> TextKit2EditorView
      -> inputAccessoryView / keyboard toolbar
```

Reason: the keyboard toolbar edits the current note text and depends on selection, first responder state, keyboard state, and platform text-input behavior. It can be extracted into an `EditorKeyboardToolbar` component later, but ownership should remain in the editor stack.

Rule of thumb:

```text
Navigates the vault/app -> VaultWorkspaceView
Edits current note text -> NoteEditorScreen / TextKit2EditorView
```

## Simplified Navigation Lifecycle

Target lifecycle:

```text
User intent
  -> VaultWorkspaceView
  -> route/selection state changes
  -> SwiftUI renders the right surface
```

All navigation decisions should be centralized in `VaultWorkspaceView`.

List/sidebar/search/editor surfaces emit intents:

```swift
openFolder(_ folder)
openNote(_ note)
openToday()
openSearch()
openSettings()
openDocumentLink(_ path)
goBack()
goForward()
```

Platform-specific presentation differs, but intent handling should be shared:

```text
Compact iPhone
  -> VaultWorkspaceView uses NavigationStack(path)

iPad/macOS
  -> VaultWorkspaceView uses NavigationSplitView(selection/detail)
```

Examples:

```text
User taps folder
  -> NoteListView emits openFolder
  -> VaultWorkspaceView updates route
  -> SwiftUI shows folder list

User taps note
  -> NoteListView emits openNote
  -> VaultWorkspaceView updates route/selection
  -> SwiftUI shows NoteEditorScreen

User taps search result
  -> NoteSearchSheet emits openNote
  -> VaultWorkspaceView closes search and opens note

User taps document link
  -> NoteEditorScreen emits openDocumentLink
  -> VaultWorkspaceView resolves and opens note route
```

## Why Not Put It All In MainAppView?

`MainAppView` can technically own everything, but then it becomes the same oversized router that `NoteListView` is today. The cleaner split is:

```text
MainAppView = app runtime lifecycle
VaultWorkspaceView = workspace navigation lifecycle
NoteListView = list rendering
NoteEditorScreen = note editing
```

## Migration Plan

1. Rename current `NoteListView` conceptually to `VaultWorkspaceView` without changing behavior.
2. Extract a smaller real `NoteListView` or `FolderListView` that only renders list rows and emits callbacks.
3. Move search/settings/Today/restore/history state into `VaultWorkspaceView`.
4. Keep `NotoSplitView` temporarily, then either fold it into `VaultWorkspaceView` or reduce it to a platform-specific split shell.
5. Once `VaultController` exists, replace direct `MarkdownNoteStore` construction in views with controller calls.

## Risks

- Navigation regressions on compact iPhone.
- iPad split-view selection and native back-stack sync regressions.
- Search result opening and document-link routing need careful rewiring.
- This touches many files, so it should be done in phases with tests around navigation state.

## Recommendation

Do this after or alongside the `VaultController` work, not before everything else. The view refactor is much easier when views emit intents to one workspace controller instead of directly constructing stores and destinations.
