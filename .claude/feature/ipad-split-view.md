# Feature: iPad Split View

## User Story

As an iPad user, I want Noto to feel like a native large-screen notes app, with a collapsible sidebar on the left and the selected note editor on the right, so I can browse notes and edit at the same time instead of using a stretched phone-style stack.

## User Flow

On iPhone-sized layouts, the app keeps the current push-based navigation.

On iPad regular-width layouts:
- The app opens in a split view.
- The app restores the last opened note when available; otherwise it opens today's note.
- The app starts with the sidebar collapsed so the editor is the primary view.
- The left sidebar shows the same folder and note navigation model as the macOS sidebar.
- Tapping a note opens it in the detail pane on the right and collapses the sidebar.
- Creating a note opens it directly in the detail pane and collapses the sidebar.
- The sidebar can be collapsed using the system split-view behavior, and restored later.
- The Today and Settings actions remain available from the top-level iPad shell.

## Success Criteria

- iPad regular-width layouts use a native `NavigationSplitView`.
- The sidebar uses the same hierarchical navigation behavior as the macOS sidebar.
- Launch restores the last opened note when possible, otherwise defaults to today's note.
- Launch presents the editor with the sidebar collapsed by default.
- Selecting a note shows `NoteEditorScreen` in the detail pane.
- Creating a note from the sidebar opens a new note in the detail pane.
- Selecting or creating a note collapses the sidebar automatically.
- Split-detail note editing does not show the iPhone-style inline back button.
- iPhone compact-width layouts keep the existing `NavigationStack` flow.
- The sidebar can be collapsed and restored with standard split-view controls.

## Tests

- `flowdeck run -w Noto.xcodeproj -s Noto-iOS -S <isolated iPad simulator> --launch-options='-notoResetState YES -notoUseLocalVault YES'`
  - Verified regular-width iPad launches into a native split view.
  - Verified cold launch restores today's note into the detail pane with the sidebar collapsed.
  - Verified creating a note from the left sidebar opens `NoteEditorScreen` in the detail pane and collapses the sidebar.
  - Verified selecting an existing note from the sidebar collapses back into the detail pane.
  - Verified split-detail note editing no longer shows the inline back button.
  - Verified the system sidebar toggle collapses the sidebar.

## Implementation Details

- Kept the existing iPhone `NavigationStack` path for compact-width iOS layouts.
- Added an iPad regular-width `NavigationSplitView` path on iOS using `horizontalSizeClass`.
- Added explicit split-view visibility state so iPad can default to `detailOnly`.
- Reused the existing sidebar selection model for split-view detail presentation.
- Added last-open-note restoration for the iPad split-view path, falling back to today's note.
- Collapsed the sidebar automatically whenever a note is opened or created in the split-view sidebar.
- Removed the custom inline iPhone back button from split-detail note editing.
- Promoted the macOS-style sidebar views into shared SwiftUI views so iPad and macOS use the same folder/note navigation model.
- Fixed nested folder navigation in the shared sidebar by passing the selected folder through the recursive sidebar rows.

## Bugs

_None yet._
