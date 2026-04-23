# TextKit-Native Rendering Phase 2: Todo Fragments

## Scope

Phase 2 migrates rendered todo checkboxes away from manually positioned overlay buttons and toward TextKit-owned layout/rendering.

Phase 1 made todo/image eligibility semantic. Phase 2 should make todo checkbox geometry come from the paragraph layout fragment itself.

## In Scope

- Add a todo-specific TextKit layout fragment.
- Draw checked and unchecked todo circles inside the fragment.
- Keep backing Markdown as `- [ ]` / `- [x]`.
- Keep hidden todo prefix metrics stable for caret placement, wrapping, and editing.
- Preserve todo tap-to-toggle behavior.
- Preserve undo/redo for toggles.
- Remove current todo overlay button rendering after parity is verified.

## Out of Scope

- Image block migration.
- XML collapse model migration.
- XML caret/gutter migration.
- Hyperlink changes.
- Changing visual list indentation beyond what is necessary for todo fragments.

## Implementation Plan

1. Add a todo fragment class.
   - Reuse `MarkdownParagraph.blockKind`.
   - The `NSTextLayoutManagerDelegate` returns the todo fragment for `.todo`.
   - Keep existing hidden prefix styling in `MarkdownParagraphStyler`.

2. Draw todo marker in the fragment.
   - Derive checkbox rect from `MarkdownVisualSpec` and the paragraph/list metrics.
   - Draw unchecked circle and checked circle/checkmark with platform colors.
   - Keep drawing platform-specific only where CoreGraphics/AppKit/UIKit diverge.

3. Replace overlay hit testing.
   - Remove `todoCheckboxButtons` refresh/add paths once fragment drawing is verified.
   - Add tap handling that maps a touch/click point to a todo paragraph and checkbox rect.
   - Toggle backing Markdown with the existing `toggleTodoCheckbox(atParagraphLocation:)`.

4. Preserve accessibility.
   - Near-term: expose tap behavior and keep the todo text readable.
   - If fragment-only accessibility is insufficient, document the gap and consider a lightweight accessibility element or attachment view provider.

## Test Plan

Unit/layout tests:

- Todo paragraph uses the todo fragment class.
- Todo marker rect aligns with the todo content caret baseline.
- Empty `- [ ] ` keeps body-sized insertion boundary.
- Checked todo still applies strikethrough to body text.
- Wrapped todo continuation lines align with first-line content.
- Nested todos draw marker at the expected indent.
- Todos inside collapsed XML ranges do not get a todo fragment.

Lifecycle tests:

- Tapping the drawn checkbox toggles Markdown from `- [ ]` to `- [x]`.
- Undo/redo works after a tap toggle.
- Expanding XML content above todos keeps marker alignment.

Visual verification:

- Seed isolated simulator vault.
- Open `Project Plan` and verify unchecked/checked todos render.
- Toggle at least one todo by tapping the marker.
- Open `Captures/The State of Consumer AI - Usage`.
- Collapse and expand highlights/content.
- Scroll to `Capture checks` and verify todo markers align with text.
- Capture screenshot evidence.

## Exit Criteria

- Current todo overlay arrays and button creation are removed for todo rendering.
- Tests cover fragment selection, drawing geometry, tap toggles, undo/redo, and collapse/expand alignment.
- iOS simulator visual verification passes.
- macOS builds; macOS tests run if scheme support is available.

## Verification Results

- `flowdeck test --only TextKit2MarkdownLayoutTests`: passed 24/24 on iPhone 16 Pro simulator.
- `flowdeck test --only TextKit2EditorLifecycleTests`: passed 13/13 on iPhone 16 Pro simulator.
- `flowdeck build -D "My Mac"`: passed.
- `flowdeck test -D "My Mac" --only TextKit2MarkdownLayoutTests`: FlowDeck resolved tests, then reported the selected macOS scheme has no executable tests.
- Visual simulator pass on isolated simulator `Noto-TextKitPhase1-0423` (`3D0DF1CD-096F-463D-A4B2-0B26B586F76C`):
  - Seeded the vault with `.maestro/seed-vault.sh`.
  - Opened `Captures/The State of Consumer AI - Usage`.
  - Confirmed image block still renders as an image.
  - Collapsed the highlights XML block and confirmed the content moves without stale todo overlays.
  - Scrolled to `Capture checks`, verified todo circles sit in the todo gutter, and tapped the first marker to toggle it checked with strikethrough.
  - Evidence: `.codex/evidence/phase2-todo-fragments/capture-checks-toggled.png`.

## Risk

`NSTextLayoutFragment` is primarily a drawing surface, not a native control host. If accessibility or hit testing becomes too brittle, the fallback is an attachment view provider for the checkbox while keeping the semantic and range model from Phase 1.
