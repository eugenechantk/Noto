# TextKit-Native Rendering Phase 5: Layout-Driven Gutter Controls

## Scope

Phase 5 keeps XML collapse carets as overlay controls, but stops positioning them from `caretRect` / `firstRect` probes. Instead, the controls derive their frames from visible `NSTextLayoutFragment` geometry for XML opening-tag paragraphs.

This preserves the architectural rule from the migration doc:
- fold controls are editor chrome, not document content
- document content should come from TextKit layout
- editor chrome should still track document layout through fragment geometry

## In Scope

- Derive XML collapse button positions from visible TextKit fragments.
- Match opening-tag paragraphs in document order to `XMLLikeTagBlock`s.
- Keep large hit targets and existing accessibility labels.
- Keep controls scoped to visible fragments only.
- Preserve collapse/expand behavior on iOS and macOS.

## Out of Scope

- Replacing the overlay controls with attachments or custom fragments.
- Changing XML parsing rules.
- Changing collapse semantics.
- Todo/image/hyperlink behavior.

## Implementation Plan

1. Add a shared geometry helper for XML collapse button frames.
2. Enumerate visible/laid-out `NSTextLayoutFragment`s and match XML opening-tag paragraphs to parsed XML blocks in document order.
3. Build the overlay button list from fragment frames instead of caret queries.
4. Re-run lifecycle tests that cover collapse-button persistence and layout shifts.

## Test Plan

Lifecycle tests:
- XML tag collapse caret survives selection changes.
- Expanding XML content realigns todo fragment hit regions after layout shifts.
- Collapsing XML content still hides native rendered content.

Visual verification:
- Open the capture note in the isolated simulator.
- Confirm both XML collapse buttons appear aligned with the opening tags.
- Collapse and expand `noto:content`.
- Confirm the button remains tappable and aligned after the layout shift.

## Exit Criteria

- No XML collapse button positioning path depends on `caretRect(for:)` or `firstRect(forCharacterRange:)`.
- Focused lifecycle tests pass.
- iOS simulator verification passes.
- macOS builds.

## Verification Results

- Focused lifecycle verification passed:
  - `flowdeck test --only TextKit2EditorLifecycleTests` -> 14/14 passed
- Cross-platform verification passed:
  - `flowdeck build -D "My Mac"` passed
- Visual verification passed on isolated simulator `Noto-TextKitPhase1-0423` (`3D0DF1CD-096F-463D-A4B2-0B26B586F76C`):
  - Opened `Captures/The State of Consumer AI - Usage`
  - Confirmed the `noto:highlights` and `noto:content` controls align with the opening-tag lines
  - Collapsed `noto:content` and confirmed the control remained tappable and changed to `Expand noto:content`
  - Expanded it again and confirmed the control returned to `Collapse noto:content`
  - Evidence screenshots saved at:
    - `.codex/evidence/phase5-gutter-controls/collapsed-control.png`
    - `.codex/evidence/phase5-gutter-controls/expanded-control.png`
- Behavioral note:
  - XML collapse controls are still overlays, but their frames now come from `NSTextLayoutFragment` geometry in document order instead of caret/frame probes.
