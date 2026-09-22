# Feature: Noto 2 Editor Options

## User Story

As a Noto 2 user editing an existing note, I can use the original Noto app's More-menu actions without adding its editor dock or AI chat.

## User Flow

1. Open a note from Noto 2 Browse or Search.
2. Open the editor action menu.
3. Use the restored non-AI menu actions.
4. Return to editing with the note state preserved.

## Success Criteria

- Noto 2 exposes Search in Note, Properties, Move Note, Delete Note, and live word/character counts in the editor More menu.
- Noto 2 does not add the original app's bottom editor dock.
- AI chat is not exposed in Noto 2.
- Actions reuse shared editor behavior where possible instead of duplicating business logic.
- Existing Noto 2 note loading, editing, autosave, and navigation continue to work.
- The restored actions are visually and interactively verified in an isolated iPhone simulator.

## Test Strategy

Use existing Swift Testing coverage for shared frontmatter, tag, move/delete, and editor-session behavior. Add Noto 2 coverage for the exact enabled action inventory. Use FlowDeck to run the app tests and verify the final editor/menu surface and representative actions in Simulator.

## Tests

### App Unit

- `Noto2Tests/NoteEditorOptionsTests.swift`
  - verifies the enabled Noto 2 action inventory matches the requested More-menu actions, without dock actions or AI chat.

### Existing Characterization and Integration

- `NotoTests/EditableFrontmatterTests.swift` — frontmatter edits used by Properties.
- `NotoTests/TagControllerTests.swift` — tag editing used by Properties.
- `Packages/NotoVault/Tests/NotoVaultTests/VaultRepositoryServicesTests.swift` — move and delete persistence.

## Implementation Details

- Move the iOS Properties sheet and `TagController` into `NotoShared` so both apps compile the same behavior.
- Extract the move-destination picker and editor action menu into `NotoShared`.
- Keep Noto 2's existing navigation chrome; do not add the original app's floating editor dock.

## Residual Risks

- The independent iOS visual-auditor agent could not start because its required model is unavailable for this account. Manual FlowDeck simulator validation covered every restored surface and route instead.
- `TagControllerTests.savePreservesOriginalCreatedAt()` remains a pre-existing failure. `TagController.swift` was moved byte-for-byte into `NotoShared`; the focused editor tests, full Noto 2 suite, and package suite pass.

## Bugs

- During simulator validation, presenting Properties initially crashed because the sheet lacked its `TagController` environment value. The sheet now receives that dependency explicitly; the rebuilt app opens Properties normally.

## Verification Results

- Noto 2 build: passed.
- Original Noto iOS build after shared-component extraction: passed.
- Noto 2 test suite: 97/97 passed after removing the dock-only routing test.
- Focused editor-option tests after the final refresh change: passed.
- NotoVault package suite: 101/101 passed.
- Isolated iPhone simulator: verified the More menu, live counts, Properties, Move Note, delete confirmation, and in-note search. Confirmed there is no editor dock or AI Chat action.
