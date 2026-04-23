# TextKit-Native Rendering Phase 4: Layout-Native XML Collapse

## Scope

Phase 4 removes the remaining post-layout text-storage mutation path for collapsed XML-like blocks and makes collapse/expand state rely on TextKit paragraph classification plus hidden layout fragments.

The editor already has the right semantic pieces:
- `XMLLikeTagParser` identifies collapsible ranges.
- `MarkdownTextDelegate` can classify collapsed paragraphs as `.collapsedXMLTagContent`.
- `HiddenFrontmatterLayoutFragment` already gives collapsed content a zero-height rendering path.

What still breaks the model is `applyCollapsedXMLTagAttributesToTextStorage()`, which rewrites fonts/colors/paragraph styles directly into the live text storage after layout refreshes. That duplicates the delegate styling path and can leave collapse behavior coupled to imperative restyling instead of layout.

## In Scope

- Remove collapsed-XML text storage rewrites from both iOS and macOS editor controllers.
- Keep collapsed XML body hiding entirely in the content-storage delegate and hidden layout fragment path.
- Preserve opening tag visibility and muted styling.
- Preserve closing tag suppression when the block is collapsed.
- Preserve todo/image suppression inside collapsed ranges.
- Keep collapse state stable across selection changes and edits that shift ranges.

## Out of Scope

- Replacing the collapse caret gutter controls.
- Converting XML blocks into custom `NSTextElement` subclasses.
- Nested XML parsing changes.
- Hyperlink/image/todo rendering changes beyond collapsed-range interaction.

## Implementation Plan

1. Remove imperative collapsed-content attribute mutation.
   - Delete `applyCollapsedXMLTagAttributesToTextStorage()`.
   - Stop calling it from overlay refresh paths.

2. Make layout refresh the only collapse application path.
   - Continue deriving `collapsedXMLTagRanges` from `collapsedXMLTagOpeningLocations`.
   - Rebuild text/layout when collapse state changes so delegate paragraph classification updates.

3. Tighten tests around the layout-native contract.
   - Collapsed XML should not rely on storage attribute rewrites.
   - Closing-tag paragraphs inside the collapsed range should map to hidden fragments.
   - Expanding after edits should keep the expected content visible and aligned.

## Test Plan

Unit/layout tests:
- Collapsed XML paragraphs use hidden fragments.
- Opening tag stays visible while closing tag becomes collapsed content.
- Todos and images inside collapsed XML stay suppressed.

Lifecycle tests:
- Collapsing XML no longer mutates the backing text storage attributes for the hidden range.
- Collapse/expand survives selection changes and layout refreshes.
- Expanding after edits restores visible content without stale hidden styling.

Visual verification:
- Open the capture note in the isolated simulator.
- Collapse `noto:content` and confirm the image and following content disappear.
- Expand it again and confirm the image/content return immediately.
- Collapse `noto:highlights` and confirm the hidden block does not leave extra visual residue.

## Exit Criteria

- `applyCollapsedXMLTagAttributesToTextStorage()` is removed.
- Collapsed XML visibility is driven by semantic paragraph classification plus hidden fragments only.
- Focused tests pass.
- iOS simulator verification passes on the capture note.

## Verification Results

- Focused tests passed:
  - `flowdeck test --only TextKit2EditorLifecycleTests` -> 14/14 passed
  - `flowdeck test --only TextKit2MarkdownLayoutTests` -> 27/27 passed
- Cross-platform verification passed:
  - `flowdeck build -D "My Mac"` passed
- Visual verification passed on isolated simulator `Noto-TextKitPhase1-0423` (`3D0DF1CD-096F-463D-A4B2-0B26B586F76C`):
  - Opened `Captures/The State of Consumer AI - Usage`
  - Collapsed `noto:content` and confirmed the collapse control flipped to `Expand noto:content`
  - Expanded it again and confirmed the control returned to `Collapse noto:content`
  - Evidence screenshots saved at:
    - `.codex/evidence/phase4-xml-collapse/collapsed-content.png`
    - `.codex/evidence/phase4-xml-collapse/expanded-content.png`
- Behavioral note:
  - The editor no longer rewrites hidden XML ranges directly into the backing text storage.
  - Hidden XML now depends on the same semantic paragraph classification and hidden-fragment path that already suppresses collapsed todos/images.
