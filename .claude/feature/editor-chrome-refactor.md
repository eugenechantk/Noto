# Feature: Editor Chrome Refactor

## Goal

Keep one shared editor owner while moving platform-specific navigation and toolbar chrome out of `NoteEditorScreen`.

## Success Criteria

- `NoteEditorScreen` still owns `NoteEditorSession` and editor lifecycle behavior.
- `TextKit2EditorView` remains the active editor path.
- Loading, download failure, remote-update banner, and editor body live in a shared content view.
- iOS navigation chrome lives in an iOS-specific helper.
- macOS toolbar chrome lives in a macOS-specific helper.
- Split-view detail can request a clean editor with no compact navigation toolbar.

## Verification

- FlowDeck iOS simulator build.
- FlowDeck macOS build.
- Focused runtime check if build changes reveal chrome regressions.
