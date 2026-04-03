# Feature: todo-items

## User Story

As a Noto user editing a markdown note, I want to create and manage todo items using standard markdown syntax so my notes stay portable while still rendering as native-looking checklist rows in the editor.

## User Flow

1. The user opens a note in the editor.
2. The user creates a todo item either by typing `- [ ] ` / `- [x] ` directly or by using the floating toolbar todo control.
3. If the user uses the floating toolbar on a normal line, the editor converts that line in place into a todo item while preserving the line text and indentation.
4. If the user uses the floating toolbar on an existing todo line, the editor converts that line back in place into a normal line while preserving the line text and indentation.
5. The editor stores the underlying markdown using the standard todo syntax `- [ ] ` and `- [x] `.
6. When a todo line is not actively being edited, the markdown prefix renders as a visual control:
   - unchecked items show an empty circle
   - checked items show a filled green circle with a checkmark
7. When the user toggles the todo state, the underlying markdown updates between `- [ ] ` and `- [x] `.

## Success Criteria

- [x] SC1: Typing `- [ ] ` creates an unchecked todo item that preserves the raw markdown in the note content.
- [x] SC2: Typing `- [x] ` creates a checked todo item that preserves the raw markdown in the note content.
- [x] SC3: The floating toolbar includes a todo control that converts the current line to or from todo formatting in place while preserving the existing line text and indentation.
- [x] SC4: Unchecked todo items render as an empty circle when the line is not active.
- [x] SC5: Checked todo items render as a filled green circle with a checkmark when the line is not active.
- [x] SC6: Toggling a todo item updates the underlying markdown between `- [ ] ` and `- [x] `.

## Tests

### Tier 2: App Unit Tests
- `NotoTests/TodoMarkdownTests.swift`
  - `testToolbarToggleAddsTodoToPlainLinePreservingIndentationAndText` — verifies SC3
  - `testToolbarToggleAddsTodoToBulletLinePreservingIndentationAndText` — verifies SC3
  - `testToolbarToggleRemovesTodoMarkerPreservingIndentationAndText` — verifies SC3
  - `testCheckboxToggleMarksUncheckedTodoAsChecked` — verifies SC6
  - `testCheckboxToggleMarksCheckedTodoAsUnchecked` — verifies SC6
- `NotoTests/MarkdownTextStorageTests.swift`
  - `testUncheckedTodoMarkdownRoundTripsUnchanged` — verifies SC1
  - `testCheckedTodoMarkdownRoundTripsUnchanged` — verifies SC2
  - `testUncheckedTodoPrefixHiddenWhenInactive` — verifies SC4
  - `testCheckedTodoPrefixHiddenWhenInactive` — verifies SC5
  - `testUncheckedTodoCheckboxAttributePresentWhenInactive` — verifies SC4
  - `testCheckedTodoCheckboxAttributePresentWhenInactive` — verifies SC5
  - `testTodoPrefixShownWhenActive` — edge case for active-line editing behavior

### Tier 3: Maestro E2E Flows
- `.maestro/notes/03_todo_items.yaml`
  - toolbar happy path: convert plain line to todo in place, then convert todo back to plain line — verifies SC3
  - typing path: enter `- [ ]` and `- [x]` directly in the editor — verifies SC1 and SC2

### Simulator Rendering Verification
- FlowDeck manual rendering check on isolated simulator
  - verify unchecked todo renders as an empty circle — verifies SC4
  - verify checked todo renders as a filled green circle with a checkmark — verifies SC5
  - verify tapping the rendered circle updates markdown state without corrupting note content — verifies SC6

## Implementation Details

Current code inspection shows partial todo support already exists in:
- `Noto/Editor/MarkdownEditorView.swift`
- `Noto/Editor/MarkdownTextStorage.swift`
- `Noto/Editor/MarkdownLayoutManager.swift`
- `NotoTests/MarkdownTextStorageTests.swift`

Current live editor path also needs parity in:
- `Noto/Editor/BlockEditorView.swift`
  - the active block editor now owns the floating toolbar todo action for iOS note editing

Likely work areas:
- add shared todo-markdown transform helpers so toolbar behavior and checkbox toggling are testable without driving UIKit directly
- change toolbar behavior from simple prefix insertion/removal to in-place line conversion that preserves indentation and existing text
- keep persisted markdown strictly in the default markdown todo syntax `- [ ] ` and `- [x] `
- add rendered checkbox metadata to text storage and draw visual circles for inactive todo lines
- add transparent checkbox overlay buttons aligned to rendered checkbox glyphs so taps work reliably without activating inline markdown editing
- align rendered visuals with the target empty/filled circle treatment using green for checked state
- add a test-only launch argument to force a local sandbox vault so Maestro and FlowDeck can validate editor features from a clean simulator
- add or update tests for markdown preservation, toolbar conversion, and rendered state metadata

## Bugs

_None yet._
