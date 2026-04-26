# Feature: Smooth scrolling for notes with inline images

## User Story

When a note contains markdown image links, scrolling currently feels noticeably
sluggish compared to text-only notes. The user expects scrolling on image-heavy
notes to feel essentially identical to scrolling on plain text — no stutter,
no dropped frames.

## Root Cause (researched, with sources)

### 1. Per-scroll-frame CG drawing for image fragments

On iOS 18+ (we run iOS 26.2), TextKit 2 calls
`NSTextLayoutFragment.draw(at:in:)` **on every scroll step** for every visible
fragment. Earlier iOS versions only re-invoked draw for non-first paragraphs;
iOS 18+ does it for all of them.

Today our `ImageLayoutFragment.draw(at:in:)`:
- Saves/restores graphics state
- Builds a rounded-rect `CGPath` clip
- Fills the placeholder background
- Looks up the source image from `MarkdownImageLoader`
- Computes an aspect-fit rect via `ImageFragmentGeometry`
- Calls `image.draw(in: drawRect)` (CPU resample even with downsampled cache)

All of that runs CPU-side per frame, into the textView's bitmap context.
There is no CALayer compositing involved — TextKit bakes everything into one
backing store.

Source: community finding cited in
[High performance drawing on iOS — Part 1](https://medium.com/@almalehdev/high-performance-drawing-on-ios-part-1-f3a24a0dcb31).

### 2. `setNeedsDisplay(textView.bounds)` is too coarse

`scheduleImageFragmentRedraw` invalidates the entire visible textView, forcing
*every* fragment to redraw — flagged as anti-pattern in the cited material:
"call `setNeedsDisplay(_:)` to mark only a small rect" and "even better, call
it on the layer using `layer.setNeedsDisplay(rect:)`".

### 3. Aspect-driven heights inflated dirty rect area

Image fragments grew from 300pt placeholder to ~493pt actual portrait height,
so each scroll frame has ~60% more pixels to push for the image rows.

## Apple's recommended pattern

Per WWDC22 *What's new in TextKit and text views* (session 10090) and the
official sample
[`apple-sample-code/EnrichingYourTextInTextViews`](https://github.com/apple-sample-code/EnrichingYourTextInTextViews),
embedded views in TextKit 2 should be `NSTextAttachment` +
`NSTextAttachmentViewProvider`. The view provider returns a real `UIView` per
attachment; the textView composites it as a CALayer-backed subview. No
per-frame CG draw — scrolling is GPU-composited.

The same architectural win — CALayer-backed subview, no per-frame CG draw —
can be reached without using `NSTextAttachment` at all, by overlaying
`UIImageView` subviews on top of the textView, parallel to the
`TodoMarkerButton` pattern this codebase already uses for todo controls.

## Two viable paths

### Path A — keep `ImageLayoutFragment` for height; overlay `UIImageView` subviews

- `ImageLayoutFragment.draw(at:in:)` becomes `super.draw` only — no clip,
  no fill, no image draw. The fragment's only job is reserving height via
  the existing memoized `layoutFragmentFrame` override.
- A single `UIImageView` (per visible image-link paragraph) holds **both
  placeholder and loaded image** in one view:
  - `backgroundColor = AppTheme.uiCodeBackground` (placeholder color)
  - `layer.cornerRadius = 8`, `layer.masksToBounds = true`
  - `contentMode = .scaleAspectFit` (GPU resample)
  - `image = loaded UIImage` once available; until then, the rounded
    background acts as the placeholder
- Lifecycle managed by `refreshImageOverlayViews()` — parallel to
  `refreshTodoMarkerButtons()`. Hooked into:
  - `refreshEditorOverlays()` (existing call site)
  - `textViewportLayoutControllerDidLayout` / scroll callbacks
  - Image-load completion (replaces `setNeedsDisplay` path)
- Mirror for macOS using `NSImageView` (`wantsLayer = true` for CALayer
  backing).

**Why we still need `ImageLayoutFragment`:** TextKit needs to know how much
vertical space the paragraph takes. Without the height override, TextKit
falls back to the paragraph style's `min/maxLineHeight` — which is set when
the paragraph is built (placeholder 300pt) and can't change after the image
loads without restyling. The fragment override is the seam through which
"image dimensions arrived → reflow" works.

### Path B — `NSTextAttachment` + `NSTextAttachmentViewProvider`

- Drop `ImageLayoutFragment` entirely.
- Content storage delegate emits a paragraph whose visible content is a
  single `\u{FFFC}` (`NSAttachmentCharacter`) plus invisible filler chars to
  keep paragraph length matched to disk storage.
- Custom `NSTextAttachment` subclass overrides `viewProvider(...)` to return
  a provider with `tracksTextAttachmentViewBounds = true`.
- Provider's `loadView()` returns the `UIImageView` (placeholder + image,
  same as Path A's overlay).
- Provider's `attachmentBounds(...)` returns the desired height
  (`containerWidth × imageH/imageW`). When the dimension cache flips from
  nil→size, calling `invalidateAttachment(...)` (or similar) prompts
  TextKit to re-ask `attachmentBounds` and reflow.
- TextKit owns the subview lifecycle — creates on viewport entry, removes
  on exit, positions during scroll. **No `refreshImageOverlayViews()`
  needed.**

### Trade-off

| | Path A | Path B |
|---|---|---|
| Diff size | Smaller — content storage delegate untouched | Larger — paragraph builder must emit attachment char + invisible chars |
| Subview lifecycle | We manage (mirrors todo markers) | TextKit manages |
| Apple WWDC22 alignment | Indirectly (same architectural idea) | Directly (the documented pattern) |
| Edge-case risk | Low — proven pattern already in this codebase | Medium — selection/cursor across invisible chars, copy/paste over attachment, edit transitions |
| Future maintenance | More code we own | Less code we own |
| Scroll performance | GPU-composited UIImageView subviews — equivalent to Path B | GPU-composited UIImageView subviews — equivalent to Path A |

**Decision:** ship Path A first. The TodoMarkerButton overlay pattern is
proven in this codebase (`refreshTodoMarkerButtons`, `todoMarkerButtons` dict,
hooked into the same lifecycle we need). Path B is the architecturally
cleaner long-term play but a bigger refactor; defer.

## User Flow

1. Open a note with `![](url)` image links.
2. While loading, each image fragment shows a rounded placeholder of the
   right height (image width × placeholder fallback or actual ratio if
   already cached).
3. As the image loads, the overlay `UIImageView` updates its `image`. No
   visible flicker, no scroll-frame stutter.
4. Scroll the note. Image fragments composite via CALayer. Scrolling feels
   smooth (60+ fps) — equivalent to a no-image note.
5. Rotation / window resize / sidebar toggle → overlays reposition; bucketed
   `displayCache` reuses or regenerates downsampled image variants.

## Success Criteria

- [x] **SC1** — `ImageLayoutFragment.draw(at:in:)` does **no CG image work**.
      Reduced to `super.draw` only.
- [x] **SC2** — A single `UIImageView` (iOS) / `NSImageView` (macOS) per
      visible image-link paragraph displays both placeholder background and
      loaded image.
- [x] **SC3** — Image overlays are positioned, sized, and recycled by
      `refreshImageOverlayViews()` mirroring `refreshTodoMarkerButtons()`.
      Hooked into `refreshEditorOverlays`, `scrollViewDidScroll`,
      `invalidateImageLayouts` (load completion).
- [x] **SC4** — Load completion calls `scheduleImageLayoutInvalidation` →
      `refreshImageOverlayViews()`. Removed `setNeedsDisplay(textView.bounds)`
      from the image load path on both iOS and macOS.
- [x] **SC5** — 84/84 markdown layout tests pass.
- [ ] **SC6** — Subjective scroll smoothness in the simulator with the test
      note. _Pending Eugene's confirmation by trying the rebuilt app._

## Tests

### Tier 1 / Tier 2

- Existing `TextKit2MarkdownLayoutTests` suite must remain green
  (geometry / cache / aspect / fragment height all unaffected).
- No new unit tests — overlay-view positioning is hard to assert without a
  live text view, and the existing TodoMarker pattern doesn't have
  dedicated unit tests either; coverage is via simulator visual + scroll.

### Simulator visual + scroll check

Open `国内终于有厂商要出了.md`, scroll through all 4 images, return to top.
Subjective: scrolling feels smooth, no jank. Compare against a no-image
note as control.

## Implementation Plan

### 1. Strip `ImageLayoutFragment.draw`

```swift
override func draw(at point: CGPoint, in context: CGContext) {
    super.draw(at: point, in: context)
    // Visual rendering happens via the overlay UIImageView managed by the
    // editor view controller. Nothing to draw here.
}
```

Keep:
- `layoutFragmentFrame` height override (with memoization)
- `renderingSurfaceBounds` width expansion
- `availableImageContentWidth` helper

### 2. Add overlay state to `TextKit2EditorViewController`

iOS:

```swift
private var imageOverlayViews: [Int: UIImageView] = [:]   // keyed by paragraph location
```

macOS:

```swift
private var imageOverlayViews: [Int: NSImageView] = [:]
```

### 3. Add `makeImageOverlayView()`

Single view that holds placeholder + loaded image:

```swift
private func makeImageOverlayView() -> UIImageView {
    let view = UIImageView()
    view.layer.cornerRadius = MarkdownVisualSpec.imagePreviewCornerRadius
    view.layer.masksToBounds = true
    view.backgroundColor = AppTheme.uiCodeBackground
    view.contentMode = .scaleAspectFit
    view.isUserInteractionEnabled = false
    return view
}
```

### 4. Add `refreshImageOverlayViews()`

Parallel structure to `refreshTodoMarkerButtons()`:

- Iterate the current renderable blocks
- For each `.imageLink` block visible in the (slightly inset) viewport:
  - Find or create the overlay (recycle from `imageOverlayViews[paragraphLocation]`)
  - Use `MarkdownTextLayout` helpers to compute the fragment's frame
    (we'll reuse the `ImageFragmentGeometry.imageRect` math)
  - Set `view.frame` to the image rect
  - If the image is cached (`MarkdownImageLoader.cachedDisplayImage(...)`),
    set `view.image`; otherwise leave nil (placeholder shows)
  - Track active locations
- Remove views whose paragraph location isn't in the active set, return
  them to a small reuse pool (or just recreate — N is small)

### 5. Hook into the existing refresh path

Add a call to `refreshImageOverlayViews()` from:

- `refreshEditorOverlays()` (already called from todo refresh sites)
- `textViewportLayoutControllerDidLayout` (if used)
- Image-load completion handler

### 6. Replace `scheduleImageFragmentRedraw` callers

When `MarkdownImageLoader.load` completes:
- Old: `scheduleImageFragmentRedraw()` → `setNeedsDisplay(textView.bounds)`
- New: `scheduleImageOverlayRefresh()` → `refreshImageOverlayViews()`

Keep `scheduleImageLayoutInvalidation()` as-is — when dimensions arrive we
still need TextKit to reflow paragraph heights.

### 7. macOS mirror

Same logic with `NSImageView` (`wantsLayer = true`, `imageScaling =
.scaleProportionallyUpOrDown`). Hook into the existing macOS overlay
refresh sites (`refreshDividerLineViews` neighborhood).

## Bugs

_None yet._
