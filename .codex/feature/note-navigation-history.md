# Feature: Note Navigation History

## User Story

As a Noto user, I want note navigation to behave like browser history so I can move back and forward through notes I recently visited from the sidebar or from note mentions.

## User Flow

1. Open note A.
2. Open note B from the sidebar or by clicking an `@` mention rendered as a document link.
3. Navigate back to note A.
4. Navigate forward to note B.

## Success Criteria

- [x] macOS has back and forward toolbar buttons in the editor/detail toolbar.
- [x] Sidebar note activation records note visits in history.
- [x] Clicking a document mention records the destination note in history.
- [x] Back/forward navigation updates the selected note without duplicating history entries.
- [x] iOS/iPadOS editor supports horizontal swipe gestures: right swipe navigates back, left swipe navigates forward.
- [x] iOS/iPadOS mention navigation participates in the same history.

## Test Strategy

- Add Swift Testing coverage for the shared history reducer/state object.
- Build the app with FlowDeck for compile verification.
- Run focused app tests where feasible.

## Tests

- `NotoTests/MarkdownNoteStoreTests.swift`
  - `noteNavigationHistoryTracksBackAndForwardVisits`
  - `noteNavigationHistoryReplacesDuplicateVisibleVisits`
  - `noteNavigationHistoryDropsForwardEntriesAfterNewVisit`

## Implementation Details

- Add a shared `NoteNavigationHistory` value type near existing note stack navigation state.
- Route sidebar and mention selection through history-aware activation closures.
- Add macOS toolbar buttons through `MacEditorNavigationChrome`.
- Add iOS/iPadOS swipe gestures to split editor content and compact editor destinations.

## Residual Risks

- Gesture recognition was compile-verified and wired through SwiftUI, but not manually exercised in Simulator during this pass.

## Bugs

_None yet._
