# Feature: textkit2-pipeline-refactor

## User Story

Refactor the current TextKit 2 note pipeline so load, edit, format, render, sync, and save are easier to reason about and align more closely with a TextKit 2-native architecture on both iOS and macOS.

The user wants the editor to stay reliable after all recent fixes, but without accumulating more ad hoc state and view-layer patches.

## User Flow

1. Open a note from the list.
2. The app loads note content, including iCloud-backed notes, through a dedicated session layer.
3. The TextKit 2 editor presents and edits that content.
4. As the user types, formatting and typing attributes stay consistent.
5. The session persists real changes, updates note metadata, and broadcasts same-process sync updates to other windows.
6. External filesystem/iCloud changes still reload safely when the current window is not dirty.

## Success Criteria

- `NoteEditorScreen` becomes a thin SwiftUI shell over a dedicated note session object.
- The note session owns load/save/sync/download state instead of scattering it across the view.
- The TextKit 2 bridge remains responsible only for editing/rendering concerns.
- Current fixes remain intact:
  - macOS external-vault save/delete behavior
  - iOS readable-first iCloud note loading
  - same-process multi-window sync
  - empty-line caret consistency
- macOS and iOS builds still pass.
- The installed macOS app is reinstalled after the refactor.

## Tests

- `flowdeck build -s "Noto-macOS" -D "My Mac" --json`
- `flowdeck build -s "Noto-iOS" -S "Noto-Test-79de6bb1" --json`
- `flowdeck test -s "Noto-macOS" -D "My Mac" --only "NotoMacOSUITests/StructuredNoteEntryUITests/testDirectVaultExistingNoteKeepsAppendedLineOnDiskWhenSwitching" --json`
- `flowdeck test -s "Noto-iOS" -S "Noto-Test-79de6bb1" --only "NotoTests/TextKit2EditorLifecycleTests" --json`
- `flowdeck test -s "Noto-iOS" -S "Noto-Test-79de6bb1" --only "NotoiOSUITests/StructuredNoteEntryUITests/testCreateNoteAndEnterStructuredMarkdown" --json`

## Implementation Details

- Added `NoteEditorSession` as the dedicated note lifecycle owner for:
  - initial content loading
  - readable-first iCloud fallback handling
  - editor-to-store persistence
  - same-process window sync conflict handling
  - external file reload decisions
  - delayed rename scheduling
  - final disappear-time persistence
- Simplified `NoteEditorScreen` into a thin SwiftUI shell that:
  - binds `TextKit2EditorView` directly to `session.content`
  - forwards view lifecycle events into the session
  - renders transient UI such as the remote-update banner and delete confirmation
- Kept `TextKit2EditorView` responsible for TextKit concerns only:
  - content storage / layout manager delegate formatting
  - typing attributes
  - editor text publication
  - focus and platform-specific view lifecycle flushing
- Updated stale store tests to match the current `MarkdownNoteStore.SaveResult` API so the regression suite reflects the real persistence contract.

## Bugs

- The existing architecture currently mixes note session lifecycle with SwiftUI view state in `NoteEditorScreen`.
- The current save/sync/iCloud path is correct but too distributed.
