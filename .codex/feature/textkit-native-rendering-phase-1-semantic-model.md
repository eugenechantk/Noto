# TextKit-Native Rendering Phase 1: Semantic Model

## Scope

Phase 1 prepares the editor for TextKit-native rendering without changing the visible rendering architecture yet.

The goal is to make markdown semantics and renderable block ranges testable and stable before replacing overlays with fragments or attachments.

## In Scope

- Add a shared semantic model for renderable markdown blocks.
- Keep `MarkdownBlockKind`, `XMLLikeTagParser`, and `MarkdownImageLinkParser` as the source of truth.
- Derive per-line renderable items from text plus collapsed XML ranges.
- Ensure todos and images inside collapsed XML content are suppressed by semantics, not by view-layer special cases.
- Add focused tests for nested/shifted ranges and source-note fixture-like content.

## Out of Scope

- Replacing todo checkbox overlays.
- Replacing image overlays.
- Reworking XML collapse layout internals.
- Changing hyperlink rendering.
- Changing visual UI behavior.

## Implementation Plan

1. Introduce a lightweight `MarkdownRenderableBlock` model.
   - Holds block kind, paragraph range, visible line range, line text, and collapsed-content state.
   - Can derive `isNativeOverlayEligible` so current overlays use semantic filtering from one place.

2. Add a `MarkdownSemanticAnalyzer`.
   - Input: document text and collapsed XML content ranges.
   - Output: ordered renderable blocks for visible markdown lines.
   - Does not own UI decisions.

3. Use the analyzer in overlay refresh paths.
   - Todo overlay refresh reads `.todo` blocks from analyzer output.
   - Image overlay refresh reads `.imageLink` blocks from analyzer output.
   - This keeps behavior unchanged while creating the seam for Phase 2 and Phase 3.

4. Keep hyperlinks as attributed inline text.

## Test Plan

Unit tests:

- XML blocks produce stable collapsed content ranges for normal tags and comment-marker tags.
- Semantic analyzer marks todos/images inside collapsed XML content as collapsed.
- Semantic analyzer still emits opening/closing XML tag lines as visible renderable blocks.
- Semantic analyzer emits todos/images outside collapsed ranges as overlay-eligible.
- Source-note fixture shape: highlights/content blocks, image block, source links, and capture-check todos all classify as expected.

Lifecycle tests:

- Existing XML collapse overlay tests continue to pass.
- Existing todo alignment after collapse/expand regression continues to pass.

Visual verification:

- Seed the simulator vault.
- Open `Captures/The State of Consumer AI - Usage`.
- Verify image preview is visible when content block is expanded.
- Collapse content block and verify image preview is hidden.
- Re-expand content block, scroll to `Capture checks`, and verify todo checkboxes align after highlight toggle.

## Exit Criteria

- Semantic tests pass.
- Existing editor lifecycle and markdown layout tests pass.
- Simulator capture-note flow passes with screenshot evidence.
- No user-visible behavior changes beyond any existing fixes already in the working tree.

## Phase 2 Gate

Do not start the todo-fragment migration until this phase is green and the semantic analyzer is the single source used by current todo/image rendering.

## Verification Results

Completed on 2026-04-23.

- `flowdeck test --only TextKit2MarkdownLayoutTests`: passed, 21/21.
- `flowdeck test --only TextKit2EditorLifecycleTests`: passed, 13/13.
- `flowdeck test -D "My Mac" --only TextKit2MarkdownLayoutTests`: FlowDeck reported that the selected macOS scheme has no executable tests for `My Mac`.
- `flowdeck build -D "My Mac"`: passed.
- Isolated iPhone simulator: `Noto-TextKitPhase1-0423`, UDID `3D0DF1CD-096F-463D-A4B2-0B26B586F76C`.
- Seeded vault with `.maestro/seed-vault.sh 3D0DF1CD-096F-463D-A4B2-0B26B586F76C`.
- Maestro capture-source flow passed on the isolated simulator.
- Screenshot evidence: `.codex/evidence/capture-source-iphone-capture-checks-after-highlight-toggle.png`.

Phase 1 is green. Phase 2 can start with todo fragment migration.
