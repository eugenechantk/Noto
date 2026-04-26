# Feature: Image preview scales to text-container width preserving aspect ratio

## User Story

As a user, when a note contains markdown image links (`![](url)`), I want each
image preview to span the editor's text-container width and scale its height to
preserve the image's natural aspect ratio. Today, image previews always reserve
a fixed 300pt height and aspect-fill that rect — wide images get vertically
clipped and tall images get horizontally clipped.

## User Flow

1. Open a note with one or more `![](url)` image links (test note:
   `~/Library/Mobile Documents/com~apple~CloudDocs/Noto/Captures/国内终于有厂商要出了.md`).
2. While the image is loading, a 300pt placeholder rect (current behavior) is
   shown — width = container width.
3. When the image finishes loading, the preview reflows to:
   - **width** = text-container width (`textContainer.size.width` minus padding)
   - **height** = `width × imageHeight / imageWidth`
4. The image is drawn aspect-fit (or, equivalently, drawn at the rect bounds
   since the rect now matches the image's ratio) — no cropping.
5. On subsequent opens of the same note within the app session, the dimension
   cache is warm — the correct height is used on the very first layout pass,
   so there is no relayout flicker.
6. On rotation / window resize / sidebar toggle, image fragment heights
   recompute from the new container width on the next layout pass.

## Success Criteria

- [x] **SC1** — `MarkdownImageDimensionCache` returns a cached `CGSize` for any
      URL whose image is present in `MarkdownImageLoader`'s image cache.
      Verified by `imageDimensionCacheStoresAndReturnsSizesPerURL`.
- [x] **SC2** — `ImageLayoutFragment.layoutFragmentFrame` returns a height of
      `containerContentWidth × imageH / imageW + 2×verticalPadding` whenever
      a size is cached for the fragment's URL.
      Verified by `aspectAdjustedFragmentHeightScalesToContainerWidth` + simulator.
- [x] **SC3** — When no dimension is cached for the URL, the placeholder
      `MarkdownVisualSpec.imagePreviewReservedHeight` (300pt) is used.
      Verified by `imageLinksReserveVerticalPreviewSpace`.
- [x] **SC4** — `ImageFragmentGeometry.aspectFillRect` is replaced with
      `aspectFitRect`. Loaded images are never clipped.
      Verified by `aspectFitRectContainsImageWithoutOverflow` and
      `imageFragmentUsesAspectFitSizing`.
- [x] **SC5** — On `MarkdownImageLoader.load` completion the dimension cache is
      populated and a layout invalidation is triggered for the document
      (coalesced via `isImageLayoutInvalidationScheduled` into a single
      runloop tick).
- [x] **SC6** — In the simulator, the test note opens with 4 portrait images
      from twimg.com, each scales to container width (~370pt) with its
      ~1.33 height/width ratio — verified visually with no clipping.
      Screenshots: `/tmp/image-aspect-after-1.png`, `/tmp/img-aspect-{1..4}.png`.

## Tests

### Tier 1: Package Tests

_None — image rendering lives in the app target, not in a package._

### Tier 2: App Unit Tests

- `NotoTests/TextKit2MarkdownLayoutTests.swift`
  - `imageLinksReserveVerticalPreviewSpace` — UPDATE: still verifies the 300pt
    placeholder when no dimension is cached. Verifies SC3.
  - `imageFragmentHeightUsesCachedAspectRatio` — NEW: seeds the dimension
    cache, queries `ImageFragmentGeometry`/styler for the resolved height,
    asserts `containerWidth × ratio`. Verifies SC1 + SC2.
  - `imageDrawRectFitsInsideFragmentBounds` — NEW: confirms the draw rect for
    a cached image matches the fragment bounds (aspect-fit, no overflow).
    Verifies SC4.

### Tier 3: Maestro E2E

_Skipped — visual rendering is not assertable via Maestro. Use the simulator
visual check below._

### Simulator Visual Check (verifies SC6)

Open the test note in the iOS simulator, screenshot before and after image
load, confirm:
- All 4 images render at full container width.
- No vertical clipping on tall images, no horizontal clipping on wide ones.
- No visible scroll jump when images finish loading (because the user starts
  at the top of the note).

## Implementation Details

### Dimension cache (`MarkdownImageDimensionCache`)

Add alongside `MarkdownImageLoader` in `Noto/Editor/TextKit2EditorView.swift`:

```swift
private enum MarkdownImageDimensionCache {
    private static let cache = NSCache<NSURL, NSValue>()
    static func cachedSize(for url: URL) -> CGSize?
    static func setSize(_ size: CGSize, for url: URL)
}
```

`NSValue` wraps `CGSize` (use `NSValue(cgSize:)` / `.cgSizeValue` on iOS, or
the equivalent macOS API).

### Loader integration

In `MarkdownImageLoader.load(url:completion:)`, on every successful
`PlatformImage` resolution (file or remote), call
`MarkdownImageDimensionCache.setSize(image.size, for: url)` before invoking
the completion handler.

### Fragment frame override

In `ImageLayoutFragment`:

```swift
override var layoutFragmentFrame: CGRect {
    let base = super.layoutFragmentFrame
    guard let height = aspectAdjustedHeight() else { return base }
    return CGRect(origin: base.origin,
                  size: CGSize(width: base.width, height: height))
}

private func aspectAdjustedHeight() -> CGFloat? {
    guard let url = imageURL(),
          let size = MarkdownImageDimensionCache.cachedSize(for: url),
          size.width > 0,
          let contentWidth = availableImageContentWidth(),
          contentWidth > 0
    else { return nil }
    return contentWidth * (size.height / size.width)
        + MarkdownVisualSpec.imagePreviewVerticalPadding * 2
}
```

`renderingSurfaceBounds` already follows `layoutFragmentFrame.height`
expansion — verify it still expands correctly.

`ImageFragmentGeometry.imageRect` continues to be the source of the draw rect.

### Aspect-fit instead of aspect-fill

In `ImageFragmentGeometry.aspectFillRect`, replace `max(scale...)` with
`min(scale...)` so the image is contained inside the rect. Rename to
`aspectFitRect` to keep the semantics honest.

### Relayout on load

Both copies of `requestImageLoad` (iOS at line ~3485, macOS at ~4929):

- Populate dimension cache on success.
- Replace `scheduleImageFragmentRedraw` with `scheduleImageLayoutInvalidation`,
  which on the next runloop tick invalidates layout for the visible viewport
  (or document range). One coalesced invalidation per batch.

### Coalescing

Re-use the existing `isImageFragmentRedrawScheduled` flag pattern but rename
to `isImageLayoutInvalidationScheduled`. Keep the redraw path for the
"image failed to load" branch.

## Bugs

_None yet._
