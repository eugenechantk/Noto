# TextKit-Native Rendering Phase 3: Image Fragments

## Scope

Phase 3 migrates Markdown image block rendering from manually positioned `UIImageView` / `NSImageView` overlays into TextKit-owned image layout fragments.

Phase 2 proved the pattern for a non-view special element: semantic paragraph metadata chooses a custom `NSTextLayoutFragment`, and the fragment owns drawing while the backing Markdown stays editable. Image blocks should follow the same model, with async image loading invalidating layout/display instead of rebuilding scroll-view overlays.

## In Scope

- Add an image-specific TextKit layout fragment for `.imageLink` paragraphs.
- Draw loaded images directly in the fragment drawing pass.
- Keep the backing Markdown image/link source in the document.
- Preserve the existing reserved image height, corner radius, and fit behavior.
- Preserve gray placeholder rendering while an image is loading or unavailable.
- Remove current image preview overlay view arrays and add/remove paths after parity is verified.
- Keep image blocks suppressed when their paragraph is inside collapsed XML content.
- Ensure scrolling stays responsive when image blocks are present.

## Out of Scope

- XML collapse control migration.
- Hyperlink behavior.
- Todo marker behavior.
- Changing image fetching policy beyond what is needed for fragment invalidation.
- Rich image interactions such as resize handles, context menus, or drag/drop.

## Implementation Plan

1. Introduce image fragment drawing.
   - Add `ImageLayoutFragment: NSTextLayoutFragment`.
   - Return it from `MarkdownTextDelegate.layoutFragment(for:)` when `MarkdownParagraph.blockKind` is `.imageLink`.
   - Draw the placeholder background and cached image into the reserved line rect.

2. Make image loading fragment-aware.
   - Reuse `MarkdownImageLoader` cache.
   - Trigger async loads from editor controllers based on semantic blocks, but invalidate TextKit display/layout instead of adding overlay image views.
   - Keep network/cache concerns outside the fragment where possible so fragments remain lightweight drawing objects.

3. Remove overlay image views.
   - Delete `imagePreviewViews` arrays and `refreshImagePreviews()` / `addImagePreview(...)` paths after fragment drawing works.
   - Keep `refreshEditorOverlays()` for XML collapse controls until a later phase.

4. Validate layout stability.
   - Image paragraphs should keep their reserved height through scroll, selection changes, and XML collapse/expand.
   - No tall extra blank line after image blocks.
   - No gray box once an image successfully loads.

## Test Plan

Unit/layout tests:

- Image paragraphs use the image layout fragment.
- Non-image paragraphs use the default fragment.
- Image fragment drawing rect preserves the reserved image height minus vertical padding.
- Collapsed XML image paragraphs use hidden fragments instead of image fragments.
- Image paragraph newline attributes keep the tiny line height and zero spacing contract.

Lifecycle tests:

- Loading a note with an image paragraph does not create image overlay subviews.
- Collapsing XML content hides image rendering.
- Expanding XML content restores image rendering without stale overlay views.

Visual verification:

- Seed isolated simulator vault.
- Open `Captures/The State of Consumer AI - Usage`.
- Confirm the image block renders an actual loaded image, not only a gray placeholder.
- Scroll past the image block and confirm there is no oversized empty line after it.
- Collapse and expand the surrounding XML content and confirm the image block remains aligned.
- Capture screenshot evidence.

## Exit Criteria

- Current image overlay arrays and image view creation are removed for image rendering.
- Tests cover fragment selection, placeholder/image geometry, collapsed XML suppression, and absence of overlay image views.
- iOS simulator visual verification passes with the capture source note.
- macOS builds; macOS tests run if scheme support is available.

## Risk

Async image loading can outlive individual layout fragments. The cache and invalidation path should be owned by the editor controller or a shared coordinator, while fragments draw only from current cached state. If TextKit invalidation is not reliable enough for loaded images, the fallback is a minimal attachment/provider path that still keeps layout ownership inside TextKit instead of scroll-view overlays.

## Verification Results

- Focused tests passed:
  - `flowdeck test --only TextKit2MarkdownLayoutTests` -> 27/27 passed
  - `flowdeck test --only TextKit2EditorLifecycleTests` -> 13/13 passed
- Cross-platform verification passed:
  - `flowdeck build -D "My Mac"` passed
- Visual verification passed on isolated simulator `Noto-TextKitPhase1-0423` (`3D0DF1CD-096F-463D-A4B2-0B26B586F76C`):
  - Seeded the simulator vault with `.maestro/seed-vault.sh 3D0DF1CD-096F-463D-A4B2-0B26B586F76C`
  - Opened `Captures/The State of Consumer AI - Usage`
  - Confirmed the image block renders a loaded image on the TextKit fragment surface
  - Confirmed the line after the image returns immediately to the source-note paragraph with no oversized blank spacer
  - Confirmed collapsing `noto:content` hides the image block and expanding restores it without overlay artifacts
  - Evidence screenshot saved at `.codex/evidence/phase3-image-fragments/image-fragment-rendered.png`
- Debug note:
  - The first fragment implementation reserved the correct height but only painted a thin strip because the fragment draw pass was clipped to the hidden markdown glyph width.
  - Fix: widen `ImageLayoutFragment.renderingSurfaceBounds` to the text container width and draw against that expanded surface instead of the glyph-only bounds.
