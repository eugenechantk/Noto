# Feature: Frontmatter Block Restart

## User Story

As a Noto user, I want frontmatter metadata shown as an expandable rounded block at the top of the editor so I can read and edit note metadata without raw YAML disrupting the document.

## User Flow

1. Open a note that has YAML frontmatter.
2. See a rounded gray metadata block aligned to the editor text column before the first visible document line.
3. Read field keys and values in the metadata block.
4. Scroll the document and see the metadata block move with the rest of the editor content.
5. Click or tap the metadata header to collapse or expand the block.
6. Click or tap non-link values to edit them.
7. Click or tap URL-like values to open them.
8. Future interaction pass: add key/value pairs from the block.

## Success Criteria

- [x] Metadata appears as a rounded rectangle block with gray fill, aligned to the main text column.
- [x] The block is a native component mounted inside the editor scroll view and reserves stable text inset before the first visible line.
- [x] Existing frontmatter fields are shown as readable key/value rows.
- [x] Non-link values become editable fields when clicked or tapped.
- [x] URL-like values are clickable hyperlinks and clicking them does not enter edit mode.
- [x] The native block can collapse and expand without leaving TextKit flow.
- [ ] Metadata includes an add row that can add a new key/value pair to the markdown frontmatter.
- [x] Empty frontmatter and populated frontmatter use stable spacing before the first visible line.
- [x] Rendering behavior works on macOS, iOS, and iPadOS using shared TextKit 2 layout code where practical.

## Platform & Stack

- **Platform:** iOS, iPadOS, macOS
- **Language:** Swift
- **Key frameworks:** SwiftUI, UIKit, AppKit, TextKit 2

## Test Strategy

- Unit tests for parsing, updating, deleting, adding, and link detection in editable frontmatter.
- App-target tests for frontmatter range edge cases, especially empty frontmatter.
- Build verification on macOS and iOS simulator.
- UI validation on iPhone and iPad simulator after implementation.

## Tests

Planned:

- `NotoTests/EditableFrontmatterTests.swift`
  - parse scalar fields
  - preserve multiline values
  - update scalar values
  - add frontmatter to plain markdown
  - add a key/value pair to existing frontmatter
  - detect URL-like values
- `NotoTests/TextKit2EditorLifecycleTests.swift`
  - empty frontmatter range is detected
  - visible first-line position is independent of empty vs populated frontmatter

## Implementation Phases

### Phase 1: Frontmatter Data Model

- Scope: Parse and render editable frontmatter fields, value link detection, add/update/delete operations.
- Success criteria covered: readable fields, add key/value pair, hyperlink detection.
- Verification gate: focused Swift tests pass.

### Phase 2: Scroll-View Component Layout

- Scope: Parse frontmatter into editor metadata, hide raw YAML paragraphs in TextKit, and render the metadata block as a native scroll-view subview inside `UITextView`/`NSTextView`.
- Success criteria covered: document-flow block, stable spacing, readable field rows, scrolls with editor text.
- Verification gate: macOS and iOS builds pass; focused hidden-frontmatter and geometry tests pass.

### Phase 3: Native Interaction

- Scope: Add native hit testing and editing controls for rows, links, and collapse/expand state without reverting to an outside-the-scroll-view SwiftUI overlay.
- Success criteria covered: inline edit, links, collapse/expand.
- Verification gate: simulator interaction validation on iPhone and iPad plus focused markdown mutation tests.

### Phase 4: Add Row

- Scope: Add native add-field affordance and commit behavior.
- Success criteria covered: add row.
- Verification gate: focused markdown mutation tests plus simulator validation.

## Bugs

_None yet._

## Verification

- `flowdeck build` on isolated iPhone simulator `Noto-FrontmatterBlock-Clean`: passed.
- `flowdeck test --only NotoTests/EditableFrontmatterTests --progress`: passed, 14 tests.
- `flowdeck test --only 'NotoTests/TextKit2EditorLifecycleTests/detectsEmptyFrontmatterRange()' --progress`: passed.
- `flowdeck test --only 'NotoTests/TextKit2EditorLifecycleTests/frontmatterCollapsedReserveIsIndependentOfFieldCount()' --progress`: passed.
- `flowdeck test --only 'NotoTests/TextKit2EditorLifecycleTests/frontmatterBlockGeometryReservesBlockHeightPlusFollowingGap()' --progress`: passed.
- `flowdeck test --only 'NotoTests/TextKit2EditorLifecycleTests/frontmatterBlockCollapsedGeometryReservesHeaderHeightOnly()' --progress`: passed.
- `flowdeck test --only 'NotoTests/TextKit2EditorLifecycleTests/frontmatterBlockHitTestingReturnsVisibleFieldIndex()' --progress`: passed.
- `flowdeck test --only 'NotoTests/TextKit2MarkdownLayoutTests/frontmatterParagraphsUseHiddenFragments()' --progress`: passed.
- `flowdeck build -s Noto-macOS -D 'My Mac'`: passed.
- iPhone simulator visual validation with seeded vault:
  - `.codex/evidence/frontmatter-textkit-rows-top.png`
  - `.codex/evidence/frontmatter-textkit-rows-scrolled.png`
  - `.codex/evidence/frontmatter-interaction-expanded.png`
  - `.codex/evidence/frontmatter-interaction-collapsed.png`
  - `.codex/evidence/frontmatter-interaction-value-editing-2.png`
  - `.codex/evidence/frontmatter-component-in-scrollview-top.png`
  - `.codex/evidence/frontmatter-component-in-scrollview-scrolled.png`
  - `.codex/evidence/frontmatter-component-collapsed.png`
- iPad mini simulator visual validation with seeded vault:
  - `.codex/evidence/frontmatter-textkit-ipad-rows.png`
  - `.codex/evidence/frontmatter-component-ipad-top.png`

Note: an initial full `flowdeck test` run reached `test-without-building` and produced no output for more than six minutes, so it was terminated and replaced with focused FlowDeck test runs against the new suites and changed lifecycle tests.
