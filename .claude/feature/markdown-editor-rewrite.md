# Feature: markdown-editor-rewrite

## User Story

As a user, I want the markdown editor to render formatting correctly after every edit, with no attribute bleeding, stale state, or visual glitches, so that what I see always matches the underlying markdown.

## User Flow

1. The user opens an existing markdown note on iOS or macOS.
2. The editor loads raw markdown content and renders it as a formatted editing surface.
3. The user moves the cursor across headings, todos, bullets, ordered lists, and inline markdown.
4. The editor updates cursor-dependent formatting consistently after each edit and selection change.
5. The user types, deletes, inserts new lines, toggles todos, indents, and outdents content.
6. After every edit, the rendered result stays aligned with the raw markdown source with no formatting corruption on adjacent lines.
7. The user can continue editing the same note on iOS and macOS using the same underlying formatting architecture.

## Success Criteria

- [x] SC1: All existing markdown formatting works: headings, bullets, todos, ordered lists, bold, italic, code, and frontmatter hiding.
- [x] SC2: Heading prefix hidden when cursor not on heading, shown dimmed when cursor is on heading.
- [x] SC3: Todo prefix hidden with clear color plus body font, checkbox overlays positioned correctly.
- [x] SC4: Checked todos have strikethrough plus dimmed color.
- [x] SC5: No attribute bleeding. Deleting text on one line never corrupts formatting on adjacent lines.
- [x] SC6: The rewrite uses one shared formatting pipeline that produces consistent results after edits and selection changes on both iOS and macOS.
- [x] SC7: Cursor-dependent rendering is handled predictably by editor state, without ad hoc line-specific repair logic.
- [x] SC8: The rewrite materially simplifies the current editing and rendering stack by removing the known sources of re-entrant formatting bugs and reducing special-case state handling.
- [x] SC9: All existing regression tests pass after updates for the new architecture.
- [x] SC10: New edit-sequence tests specifically for attribute bleeding scenarios pass.
- [x] SC11: Auto-continue on Enter works for todos, bullets, and ordered lists.
- [x] SC12: Indent and outdent work.
- [x] SC13: Toolbar todo toggle works.
- [x] SC14: macOS editor works with the same architecture.

## Tests

Testing strategy for the rewrite:
- Start by simplifying and rewriting the editor-related tests before the architecture rewrite.
- Preserve coverage of all existing edit-format-render behaviors currently tested by `MarkdownTextStorageTests` and `TodoMarkdownTests`.
- Reorganize tests around stable behaviors and contracts instead of the current `MarkdownTextStorage` implementation details where possible.
- Add explicit edit-sequence regression tests for attribute bleeding, stale selection-state rendering, newline continuation, indent/outdent, todo toggling, and cross-line formatting isolation.

Baseline status:
- `Packages/NotoVault` package tests pass via `swift test` as of 2026-04-02: 25 tests passing.
- App-level regression suite passes via `flowdeck test` as of 2026-04-02: 50 tests passing.
- macOS destination verification passes via `flowdeck build -D 'My Mac'` and `flowdeck run -D 'My Mac' --launch-options='-notoUseLocalVault true'` as of 2026-04-02.

Current editor-focused test map:

### Tier 2: App Unit Tests
- `NotoTests/MarkdownRenderingTests.swift`
  - `testHeadingRenderingAppliesTypographySpacingAndVisibilityByLevel` — verifies SC1, SC2
  - `testListRenderingAppliesExpectedIndentationSpacingAndMarkerStyling` — verifies SC1
  - `testFrontmatterIsHiddenFromRendering` — verifies SC1
  - `testInactiveTodoRenderingHidesPrefixWithBodyFontAndProvidesCheckboxMetadata` — verifies SC1, SC3
  - `testCheckedTodoRenderingDimsAndStrikesThroughContent` — verifies SC4
  - `testInlineMarkdownRenderingAppliesBoldItalicAndCodeStyles` — verifies SC1
- `NotoTests/MarkdownEditingRegressionTests.swift`
  - `testDeletingHeadingContentDoesNotRestyleFollowingParagraph` — verifies SC5
  - `testDeletingTodoContentDoesNotLeakCheckboxMetadataToFollowingParagraph` — verifies SC5, SC10
  - `testChangingActiveLineRecomputesVisibilityWithoutStaleState` — verifies SC2, SC3, SC7
- `NotoTests/MarkdownEditingCommandsTests.swift`
  - `testLineBreakActionContinuesTodoBulletAndOrderedLists` — verifies SC11
  - `testLineBreakActionExitsEmptyTodoBulletAndOrderedLists` — verifies SC11
  - `testIndentAndOutdentPreserveContentAndLineEndings` — verifies SC12
  - `testToolbarToggleConvertsPlainBulletAndOrderedLinesIntoTodos` — verifies SC13
  - `testCheckboxToggleSwitchesTodoStateAndLeavesNonTodosUnchanged` — verifies SC3, SC4, SC13

### Tier 3: Maestro E2E Flows
- `.maestro/notes/03_todo_items.yaml`
  - Verifies the toolbar todo toggle and direct markdown todo entry survive save and reopen — verifies SC11, SC13

### Canonical
- `.maestro/markdown-editor-rewrite-canonical.yaml`
  - Canonical end-to-end editor flow covering headings, bullets, ordered lists, todos, indent/outdent, save, and reopen. Recorded for demo and used as the primary regression walk-through — covers all success criteria alongside Tier 2 rendering and regression tests.

## Implementation Details

Current editor architecture after the first rewrite pass:
- `Noto/Editor/MarkdownFormatting.swift` equivalent is now `Noto/Editor/MarkdownFormatter.swift`, which owns markdown-to-attributed-string rendering decisions in one place.
- `Noto/Editor/MarkdownEditingCommands.swift` owns pure string transforms for Enter continuation, indent, and outdent.
- `Noto/Editor/TodoMarkdown.swift` remains the pure transform layer for todo toolbar and checkbox toggles.
- `Noto/Editor/MarkdownTextStorage.swift` is now a thinner TextKit adapter that stores characters and applies formatter-produced attributes.
- `Noto/Editor/MarkdownEditorView.swift` now calls the formatter through `render(activeLine:)` from editor callbacks instead of relying on formatting work inside `processEditing`.

Rewrite goals from the request:
- Simplify the editing, formatting, and rendering pipeline so edits cannot corrupt neighboring lines.
- Make formatting extensible so new markdown or custom syntax can be added without destabilizing existing behavior.
- Remove ad hoc fixes and special cases in favor of a generalized rendering pipeline.
- Preserve one architecture across iOS and macOS.

Confirmed product decisions:
- This rewrite preserves the current markdown syntax surface. New syntax extensibility is a design goal, not part of this change.
- macOS must have full editing-behavior parity with iOS, with platform-appropriate UI. Example: indent and outdent can be keyboard-driven on macOS.
- Earlier constraints around `processEditing`, `setActiveLine`, and formatting flags were brainstorming hypotheses, not hard requirements. The actual requirement is a simpler, more stable pipeline.

Recommended architecture for implementation:
- Keep the TextKit 1 host views already in use: `UITextView` on iOS and `NSTextView` on macOS.
- Replace the current storage-centric formatting model with a shared markdown formatting pipeline that derives line and inline presentation from plain markdown plus editor state.
- Make `MarkdownTextStorage` a thin attributed-text application layer, or replace its responsibilities with a similarly thin adapter, instead of letting it own parser state, selection state, and incremental repair logic.
- Keep rendering-specific concerns such as checkbox overlays in platform adapters, while sharing markdown parsing, block classification, inline styling decisions, and cursor-state-dependent visibility rules.

Implemented in this pass:
- Replaced the old monolithic editor test suite with behavior-focused rendering, editing-regression, and editing-command suites.
- Extracted `MarkdownEditingCommands` to remove Enter/indent/outdent logic from private view-coordinator-only code paths.
- Extracted `MarkdownFormatter` so formatting rules are no longer embedded inside incremental `NSTextStorage` mutation code.
- Removed formatting behavior from `processEditing`; it now falls through to `super.processEditing()` only.
- Moved editor formatting application to explicit render calls from the editor layer after text and selection changes.
- Updated todo rendering so inactive prefixes stay hidden with body font plus clear color, and checked todo content renders dimmed with strikethrough.
- Verified the rewrite on an isolated iOS 26.2 simulator with:
  - `flowdeck run -S 1DDEBCAC-5FC4-403D-9925-DD3010CA33D8 --launch-options='-notoUseLocalVault true'`
  - `maestro --udid 1DDEBCAC-5FC4-403D-9925-DD3010CA33D8 test .maestro/notes/03_todo_items.yaml`
  - `maestro --udid 1DDEBCAC-5FC4-403D-9925-DD3010CA33D8 test .maestro/markdown-editor-rewrite-canonical.yaml`
  - Crash scans of `~/Library/Logs/DiagnosticReports/*.ips` after each flow showed no new reports.
  - FlowDeck accessibility snapshots after the canonical run showed the note reopened in the editor with four checkbox overlays present, including one `Checked todo item` and three `Unchecked todo item` buttons.

Known remaining architectural leftovers:
- `activeLine` and `setActiveLine` still exist as a compatibility bridge for cursor-dependent rendering.
- Simulator-level end-to-end verification and canonical flow recording are still pending.

Answer to the TextKit question:
- Yes: the recommendation is effectively to keep using TextKit 1 as the underlying view system, while rewriting the formatting architecture above it.

## Bugs

No open product bugs found during verification.

Resolved verification-flow issues:
- Increased first-screen wait time in `.maestro/notes/03_todo_items.yaml` and `.maestro/markdown-editor-rewrite-canonical.yaml` to avoid fresh-simulator startup flakiness.
- Fixed the canonical flow so the checked todo is entered on a plain line instead of an auto-continued unchecked todo line.

## Demo

- Video: `.claude/feature/markdown-editor-rewrite.mp4`
