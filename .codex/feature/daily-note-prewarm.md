# Feature: Daily Note Prewarm

## User Story

As a Noto user, I want today's daily note to open instantly so that the first Today tap does not wait on file creation.

## User Flow

1. User opens Noto.
2. The main UI appears without waiting for daily-note creation.
3. Noto opportunistically creates today's daily note in the background.
4. User taps Today and the existing daily note opens immediately.
5. If the app remains active across local midnight, Noto creates the new day's daily note shortly after midnight.

## Success Criteria

- [x] App launch does not synchronously create/read today's note on the main launch path.
- [x] Today's note is prewarmed after app startup.
- [x] The app schedules a new prewarm after local midnight while active.
- [x] Tapping Today still creates the note as a fallback if prewarm did not run.
- [x] Daily-note creation remains idempotent for a given date.

## Test Strategy

Swift Testing covers deterministic filesystem creation and local-midnight scheduling logic. Runtime launch responsiveness is protected by keeping creation inside a detached utility task, not in SwiftUI body or foreground refresh.

## Tests

- `NotoTests/MarkdownNoteStoreTests.swift`
  - `testDailyNoteFileCreatesRequestedDate` verifies date-specific creation and template content.
  - `testDailyNoteFileCreationIsIdempotentForRequestedDate` verifies repeated prewarm calls do not rewrite.
  - `testDailyNoteNextStartOfDayUsesCalendarTimeZone` verifies local-midnight scheduling.

## Implementation Details

Daily-note file creation is extracted into `DailyNoteFile`, a non-UI helper that can run off the main actor. `MarkdownNoteStore.todayNote()` uses the same helper as the tap-time fallback. `DailyNotePrewarmer` owns startup and midnight tasks from `MainAppView`.

## Verification

- `flowdeck test --only DailyNoteTests --json` passed 10/10 tests.
- `flowdeck test --test-targets NotoTests --json` built and ran, with 211/214 passing. The three failures were outside the daily-note path:
  - `TextKit2EditorLifecycleTests/pageMentionSuggestionRowsKeepHorizontalInsetInsidePopover`
  - `NoteEditorSessionTests/editorAutosaveIsDebouncedWhileTyping`
  - `NoteEditorSessionTests/titleEditDebouncesNoteRename`
- `flowdeck test --only NoteEditorSessionTests --json` passed 5/5 on rerun.
- `flowdeck test --only TextKit2EditorLifecycleTests --json` was stopped after several minutes with no test output from the rerun.

## Residual Risks

iOS does not guarantee an exact midnight wake when the app is suspended or killed. The tap-time fallback remains required.

## Bugs

_None yet._
