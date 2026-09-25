# Feature: Noto 2 Directory Create Actions

## User Story

As a Noto 2 user browsing a directory, I can create a note or subfolder from the directory's trailing top-bar actions so new content is placed in the directory I am currently viewing.

## User Flow

1. Open Browse and navigate into a directory.
2. Use the trailing More actions menu in the directory top bar.
3. Choose **New Note** to create a note in the open directory and open it for editing.
4. Choose **New Folder** to enter a folder name, create it inside the open directory, and remain in the refreshed directory listing.

## Success Criteria

- [x] SC1: Every opened directory in Noto 2 Browse exposes a trailing More actions control.
- [x] SC2: The menu offers **New Note** and **New Folder** with native, recognizable symbols.
- [x] SC3: **New Note** creates the note in the currently displayed directory and navigates to its editor.
- [x] SC4: **New Folder** prompts for a name, creates the subfolder in the currently displayed directory, and refreshes the list.
- [x] SC5: Empty or whitespace-only folder names cannot be submitted.
- [x] SC6: The new controls have stable accessibility identifiers for UI automation.

## Test Strategy

Use Swift Testing for the directory-action model's name normalization and target-store behavior. Use an isolated Noto 2 simulator to verify menu presentation, directory-scoped note creation/navigation, folder-name validation, and refreshed folder rendering.

## Tests

### App-target unit and integration

- `Noto2Tests/ExplorerSortingTests.swift`
  - `newNoteTargetsTheDisplayedDirectoryAndOpensAsNew` — verifies SC3.
  - `newFolderTrimsItsNameAndTargetsTheDisplayedDirectory` — verifies SC4 and SC5.
  - `whitespaceOnlyFolderNameIsRejected` — verifies SC5.

### Simulator interaction

- Open a nested directory and verify the More actions control and both labeled menu commands — verifies SC1, SC2, and SC6.
- Create a note and verify the pushed editor is focused for immediate typing — verifies SC3.
- Create a named subfolder and verify it appears in the same directory list — verifies SC4 and SC5.

## Implementation Details

- Keep the menu and naming-sheet state local to `FolderListView`, because each rendered folder screen already owns the exact `MarkdownNoteStore` representing its directory.
- Render the directory header as an in-hierarchy SwiftUI top bar so root Settings, nested Back, and the trailing native menu remain visually balanced and expose stable runtime accessibility identifiers.
- Route mutations through a small app-target `ExplorerDirectoryActions` seam so directory targeting and name normalization are covered by Swift Testing.
- Carry an `isNew` bit in the note navigation destination so a note created from Browse receives the editor's established autofocus behavior.

## Residual Risks

- SwiftUI reports the visually disabled empty-name Create button as accessibility-enabled, but runtime taps on empty and whitespace-only input are verified no-ops. All requested behavior and identifiers otherwise passed the independent simulator audit.

## Verification

- Focused `ExplorerDirectoryActionsTests` run: 6 tests passed, 0 failed (the name filter also included the existing Explorer sorting suite).
- Full Noto 2 test run: 110 tests passed, 0 failed.
- Independent simulator audit: PASS for SC1-SC6. Evidence: `.codex/evidence/20260925-133648-ios-visual-audit/evidence.md`.

## Bugs

None yet.
