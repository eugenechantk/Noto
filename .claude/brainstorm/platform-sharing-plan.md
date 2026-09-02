# Maximising Shared Code Across iOS / iPadOS / macOS

**Principle:** share everything; fork only what genuinely cannot be shared.

**Status:** plan — 2026-08-03. Measurements from `main` @ `bd09d1d`.

---

## Where we actually are

| Metric | Value |
|---|---|
| `TextKit2EditorView.swift` shared | **26%** (2,167 / 8,034 lines) |
| iOS-only | 41% (3,363) |
| macOS-only | 31% (2,502) |
| Functions implemented in **both** forks | **79** |
| …of which effectively identical | **38 (48%)** — 26 byte-identical after normalising `UIColor`/`NSColor`, 12 more at 95–100% |
| App-target totals (`scripts/check_platform_parity.py`) | 243 unpaired, 33 redundant across 55 files |

Half the duplication has no reason to exist. Each instance is a place where a fix on one
platform silently cannot reach the other.

## Why the drift happens

It is structural, not a discipline failure.

1. **The typealias layer stops at value types.** `PlatformFont`, `PlatformColor`, `PlatformImage`
   exist and work. There is no `PlatformView`, `PlatformButton`, `PlatformBezierPath`,
   `PlatformEdgeInsets` — so *any* code touching views or drawing is forced to fork.

2. **Drawing was put in overlay views instead of layout fragments.** This is the whole todo bug:

   | | Where it's drawn | Result |
   |---|---|---|
   | Bullets | `TodoLayoutFragment` / paragraph styling — TextKit 2, cross-platform | Works on both |
   | Todo checkbox | `TodoMarkerButton`, a `UIView` overlay inside `#if os(iOS)` | **iOS only** |

   `TodoLayoutFragment.draw` currently just calls `super.draw` — it reserves the space but
   paints nothing, so macOS gets an indent and no glyph.

3. **The tested code is the shared code.** 67 tests cover `MarkdownVisualSpec`,
   `MarkdownBlockKind`, `TodoMarkerGeometry`, `MarkdownParagraphStyler`. The forked overlay
   layer has ~zero coverage because `UIButton` code needs a simulator. Moving code across the
   fence makes it testable — the refactor pays for itself in coverage.

## The key fact we are under-using

**TextKit 2 is cross-platform.** `NSTextLayoutFragment`, `NSTextContentStorage`,
`NSTextLayoutManager`, `NSTextParagraph`, `NSTextSelection`, `NSTextRange` are the *same types*
on iOS and macOS. Anything expressed in TextKit 2 is shared by construction.

**And `NotoTests` already runs on both the `Noto-iOS` and `Noto-macOS` schemes.** The
cross-platform verification harness exists; it just isn't asserting parity yet.

---

## Target architecture

Four layers, ordered by how platform-bound they are:

```
L0  Pure logic — no framework import
    markdown parsing, block detection, geometry, find, text transforms
    → Packages/NotoEdit, verified by `swift test`, no simulator

L1  TextKit 2 — cross-platform framework types
    layout fragments, content-storage & layout-manager delegates,
    attribute application, ALL glyph drawing
    → shared source, runs on both schemes

L2  Platform-aliased views
    view/button/path code written once against Platform* typealiases
    → shared source

L3  Genuine platform adapters — the ONLY #if os() code
    touch vs mouse, keyboard vs menu-bar commands, UIKit/AppKit
    lifecycle & delegate entry points, accessory toolbar vs inspector
```

**The rule:** code may not sit in a lower layer than it needs to. Anything in L3 that does not
touch a platform-exclusive API is a defect, and `check_platform_parity.py` is how we find it.

---

## Migration order

Lowest risk first. Each step is independently shippable and independently verifiable.

### 1. Extend the typealias layer — LOW risk, mechanical

Add alongside the existing three:

```swift
#if os(iOS)
typealias PlatformView = UIView
typealias PlatformButton = UIButton
typealias PlatformBezierPath = UIBezierPath
typealias PlatformEdgeInsets = UIEdgeInsets
#elseif os(macOS)
typealias PlatformView = NSView
typealias PlatformButton = NSButton
typealias PlatformBezierPath = NSBezierPath
typealias PlatformEdgeInsets = NSEdgeInsets
#endif
```

`NSBezierPath` needs a small shim (`addLine(to:)` vs `line(to:)`, `appendArc` naming).
Unblocks steps 2 and 3.

### 2. Hoist the 38 redundant functions — LOW risk

`check_platform_parity.py` lists them with line numbers. Each is: delete the macOS copy, move
the iOS copy outside the `#if`, retype through `Platform*`. Run tests after each.

Expected: shared share of the editor moves from 26% toward ~45%.

### 3. Move glyph drawing into layout fragments — ✅ DONE 2026-08-03

Shipped as the pilot for the L1 pattern. What it took:

- `TodoMarkerRenderer` — the glyph described once, pure `CGContext`, no `#if`.
- `TodoLayoutFragment.draw` paints it on macOS; `TodoMarkerButton.draw` delegates to the same
  renderer on iOS, so the button is now a tap target that happens to draw, not the definition
  of the artwork.
- `TodoLayoutFragment.renderingSurfaceBounds` widened to include the marker. **This was the
  non-obvious part** — the marker sits left of the text origin, so a correct rect was being
  computed and then clipped to nothing.
- Coordinate gotcha: the fragment's draw origin is already at the paragraph's text inset, so
  `contentLeadingX` must be `0`, not `todoTextStartOffset`. Passing the offset counted the
  indent twice and parked the circle on the first character.

Verified: iOS pixel-identical to before, macOS now matches it, and
`NotoTests/TodoMarkerRendererTests.swift` (ungated) passes 5/5 on **both** schemes.

Still open: click-to-toggle on macOS is expected to work — hit-testing already existed and
shares `TodoMarkerGeometry` with the drawing — but has not been verified end-to-end, which
needs cursor-taking automation.

### 4. Extract pure logic to `Packages/NotoEdit` — MEDIUM risk

Geometry, find, string, and transform helpers have no UIKit/AppKit dependency. In a package
they are shared by construction and testable via `swift test` with no simulator.

### 5. Parity gate in CI — LOW risk

`scripts/check_platform_parity.py --strict` on PRs. Converts this class of bug from
"found months later" into a failed build. Add a small allowlist for genuinely one-sided
symbols so the signal stays high.

### 6. Parity assertions in the shared test suite — partially done

`NotoTests` runs on both schemes, but **two files opt out**:

| File | Tests | Status |
|---|---|---|
| `TextKit2MarkdownLayoutTests.swift` | 67 | `#if os(iOS)` — macOS gets **no** markdown-layout coverage |
| `ChatTranscriptRestorationTests.swift` | 5 | `#if os(iOS)` |
| `TodoMarkerRendererTests.swift` | 5 | ungated ✅ — runs on both (added 2026-08-03) |

The 67-test file is the biggest single win available. Its UIKit usage is only `UIColor` (16),
`UITraitCollection` (8), and `UIFont` (5). `UIColor`/`UIFont` already have `PlatformColor` /
`PlatformFont` aliases; only the trait-collection colour resolution needs a shim
(`NSAppearance` on macOS). Ungating even the trait-free subset would give macOS real coverage
of the shared markdown layer for the first time.

Pattern to follow: assert *rendering intent* (does a todo block actually paint?), not only
geometry maths — geometry was already shared and tested, and still the marker never appeared.

---

## Known false positive in the checker

Pairing is by function name, so `indentSelectedLines` (iOS) vs `handleIndentCommand` (macOS)
reads as unpaired though both exist. Worth keeping visible: divergent naming for identical
behaviour is itself a drift vector, and converging the names is cheap.

---

## Sequencing note

Steps 1 and 2 are mechanical and safe — good first PR. Step 3 fixes a live shipping bug and
proves the L1 pattern, so it is the one that changes how future work gets written. Steps 4–6
lock the gains in so the ratio cannot silently regress.
