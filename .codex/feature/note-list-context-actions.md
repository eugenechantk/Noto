# Feature: Note List Context Actions

## User Story

As a Noto user, I can long-press a note row to reveal the actions available for that note without opening it.

## User Flow

1. Long-press a note row in a folder's note list or sidebar list.
2. A native context menu appears with Move and Delete.
3. Choosing Move presents the existing folder destination picker and moves the selected note after a destination is chosen.
4. Choosing Delete presents a destructive confirmation before deleting the selected note.

## Success Criteria

- SC1: Long-pressing a note row opens a native context menu without opening the note.
- SC2: The menu contains Move and Delete actions with familiar SF Symbols.
- SC3: Move opens the existing destination picker for the pressed note and moves it through the workspace intent path.
- SC4: Delete is visually destructive, requires confirmation, and deletes the pressed note through the workspace intent path.
- SC5: Normal taps continue to open notes, and folders do not gain these note-only actions.
- SC6: The interaction works in both compact iPhone file lists and regular-width iPad sidebar lists.

## Test Strategy

- Swift Testing covers the context-action catalog, labels, symbols, and destructive semantics.
- Existing store tests continue to cover filesystem move/delete behavior.
- Simulator interaction evidence covers long-press presentation, menu contents, Move sheet presentation, Delete confirmation, and unchanged tap behavior on iPhone and iPad.

## Tests

### App Unit

- `NotoTests/NoteListViewTests.swift`
  - verifies the context menu exposes exactly Move and Delete
  - verifies Delete is the only destructive action
  - verifies the action labels and symbols used by the menu

### Existing Integration

- `NotoTests/MarkdownNoteStoreTests.swift`
  - existing move and delete suites verify the underlying filesystem mutations

### Results

- `NoteListViewTests`: 2 passed, 0 failed
- `MoveNoteTests`: 7 passed, 0 failed
- `testDeleteNote`: 1 passed, 0 failed

## Implementation Details

- Add a small context-action model next to the note-list view.
- Attach a native SwiftUI context menu to note buttons only.
- Keep sheet/dialog presentation local to `DirectoryContentListView` while routing mutations outward through `VaultWorkspaceIntent` callbacks.
- Reuse `MoveNoteDestinationPicker` and the existing workspace move/delete intent handlers.
- iPhone simulator verification confirmed menu presentation, Move picker, successful move, Delete confirmation, successful delete, and unchanged tap-to-open behavior.
- Independent visual audit passed SC1-SC5 on a separately built and seeded iPhone simulator; evidence is in `.codex/evidence/20260925-125454-ios-visual-audit/evidence.md`.

## Residual Risks

- iPad regular-width runtime behavior remains unverified because the repository's FlowDeck isolation hook bound both sessions to dedicated iPhone simulators and rejected the iPad target. The iPad sidebar uses the same `DirectoryContentListView` implementation, but that source-level fact is not presented as runtime proof.

## Bugs

None yet.
