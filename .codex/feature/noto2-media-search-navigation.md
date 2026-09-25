# Feature: Compact Media toolbar and dedicated search

## User Story
Browse saved media without a large title, permanent search field, or file-type filters. Search is a top-bar action that opens its own view.

## User Flow
Media shows the masonry board under a centered headline matching Browse. Tap the toolbar magnifying glass to push Search Media with a focused search field. Results continue to match note content and saved link metadata. Open a result's note, then Back to the same query/results. Back again returns to the complete board. Starting another search begins with an empty query.

## Success Criteria
1. Media title matches Browse's inline principal headline; no large title, subtitle, persistent search field, or type chips remain on the board.
2. Toolbar search pushes a dedicated search view with initial keyboard focus and an accessible Clear action.
3. Note-content and cached link-metadata queries still find the correct media across all types.
4. Result opens the exact source note; Back preserves query/results; leaving search restores all media.
5. Empty results, Clear, and reopening search work without stale filters.

## Tests and Verification
This change is SwiftUI presentation/navigation only; the existing NotoVault search regression suite covers unchanged matching semantics. No new parsing or business logic. Run the full NotoVault suite, then build/run via FlowDeck and an independent recorded iPhone UI audit. Compare Media and Browse title screenshots, exercise body/metadata queries and navigation, Clear, empty results, and search reentry.

## Implementation
Keep the existing background scan and cache refresh ownership in MediaBoardScreen. Share board rendering between the complete library and search destination. Search view owns keyboard focus; the parent retains query state while visiting source notes. Remove type selection state and controls from the UI.

## Verification Results
Full NotoVault suite passed: 113 tests in 17 suites. Log: `.codex/evidence/20260926-media-toolbar/vault-tests.log`. Scoped whitespace check passed. Final Noto2 build/run passed on isolated iPhone 17 / iOS 26.3. Captured board and Browse reference show matching compact centered titles and the simplified board. Independent recorded iPhone audit PASS: all five criteria verified, including body/metadata queries, exact source navigation, preserved search on Back, Clear, no results, full board after exit, and blank focused search on reentry. Report: `.codex/evidence/20260926-001333-ios-visual-audit/evidence.md`; recording: `media-toolbar-search-flow.mov` (255.13 seconds, decode verified).

## Residual Risks
iPad runtime was not verified because the session is bound to one isolated iPhone simulator. The simulator hardware-keyboard configuration hides the software keyboard; focus was verified by a caret and successful typing immediately after navigation, without tapping the field. The broader app suite was not rerun for this presentation-only change; final build/run, NotoVault regression suite, and the recorded interaction audit passed.
