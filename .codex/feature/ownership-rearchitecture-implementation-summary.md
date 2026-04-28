# Ownership Rearchitecture Implementation Summary

Date: 2026-04-27

## Implemented Shape

```text
MainAppView
  owns app launch/lifecycle tasks
  owns root MarkdownNoteStore compatibility instance
  owns file watcher and daily note prewarmer
  renders VaultWorkspaceView

VaultWorkspaceView
  owns workspace-level navigation state
  owns compact iPhone NavigationStack routes
  owns iPad/macOS split selection state
  owns global search/settings/Today presentation state
  delegates split rendering to NotoSplitView

VaultController
  owns app-facing vault operations
  wraps current MarkdownNoteStore compatibility behavior
  is the editor/session-facing persistence boundary

SearchIndexController
  owns app-facing search-index lifecycle side effects
  posts .notoSearchIndexDidChange
  delegates package mechanics to NotoSearch.SearchIndexCoordinator

NotoVault
  owns coordinated filesystem mechanics
  owns note/folder/path/daily-note/attachment services
  contains no SwiftUI/UIKit/AppKit presentation imports

NotoSearch
  owns search index refresh/debounce/single-flight mechanics
  contains no NotificationCenter app side effects

NoteEditorSession
  owns editor-local state, autosave debounce, rename debounce, conflict state
  routes persistence through VaultController

TextKit2EditorView
  remains the native text editing/rendering surface
```

## Remaining Compatibility Layers

- `MarkdownNoteStore` still exists as the app-facing compatibility adapter for list/editor call sites.
- `CoordinatedFileManager` still exists as a small app compatibility wrapper over `NotoVault.CoordinatedVaultFileSystem`.
- `NotoSplitView` still renders platform split chrome and editor detail, but its search presentation state is owned by `VaultWorkspaceView`.

## Guardrails Added

- App tests fail if production source reintroduces `SearchIndexRefreshCoordinator`.
- App tests fail if `NotoSearch` starts posting app notifications.
- App tests fail if `NotoVault` imports SwiftUI/UIKit/AppKit presentation frameworks.
