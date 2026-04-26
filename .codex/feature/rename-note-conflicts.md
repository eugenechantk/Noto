# Feature: Rename Note Conflicts

## User Story

As a Noto user, I want note renaming to preserve every file by choosing an available filename when another note already has the target title.

## User Flow

1. Create or edit a note title.
2. The editor saves the note and asks the store to rename the backing file.
3. If `<Title>.md` already exists, Noto renames the file to `<Title>(2).md`, then `<Title>(3).md`, and so on.

## Success Criteria

- [x] Renaming a note to a title whose filename already exists appends `(2)`.
- [x] Renaming with multiple filename conflicts appends the first available suffix.
- [x] Daily notes keep their ISO date filename.
- [x] Existing move-note conflict behavior remains unchanged.

## Test Strategy

Use app-target Swift Testing against real temporary vault directories.

## Tests

- `NotoTests/MarkdownNoteStoreTests.swift`
  - `testRenameFileConflictAppendsSuffix`
  - `testRenameFileMultipleConflictsAppendsFirstAvailableSuffix`
  - existing daily-note and move-note conflict tests

## Implementation Details

Reuse `MarkdownNoteStore.resolveConflict(for:in:)` in `renameFileIfNeeded(for:)`, matching move-note behavior.

## Verification

- `flowdeck test --only 'NotoTests/FileRenameTests' --only 'NotoTests/MoveNoteTests'` passed: 22 tests.

## Residual Risks

No UI validation needed; this is non-visual filesystem behavior.

## Bugs

None yet.
