# Bug 026: Some inline images are not rendered in the macOS app

## Status: PARTIALLY FIXED — verified 2026-08-05 (73 of 585 lines; 512 remain, see Remaining Work)

## Description

Eugene reports that some inline images do not render in the desktop (macOS) app,
citing the note `Ideas/AI photo ∕ video editing ∕ generation.md`.

**What happens:** the image line stays as raw markdown text (or nothing visible)
instead of showing the picture.
**What should happen:** the image renders inline.

## Reproduction attempt — the cited note

Could **not** reproduce on `Ideas/AI photo ∕ video editing ∕ generation.md`.
The image at line 28 (`![...](.attachments/Screenshot%202026-05-02%20at%201.01.03%E2%80%AFPM.png)`)
rendered correctly in every configuration tried:

| Build | Window | Result |
|---|---|---|
| Fresh Debug build of current source | 1400×1000, sidebar open | renders |
| Fresh Debug build, cold launch | 1400×1000 | renders |
| Installed `/Applications/Noto.app` (Aug 3 build) | 1400×1000 | renders |
| Installed app | 568×1000 (Eugene's saved size, editor ~226pt wide) | renders |

Evidence: `scratchpad/noto-04.png`, `noto-05.png`, `noto-06.png`, `noto-07.png`, `noto-10.png`.

Supporting checks:
- Path resolution + coordinated read of that attachment succeed outside the app
  (standalone Swift probe: resolves to the right file, 3 583 416 bytes, decodes to 2132×1556).
- `.attachments/` files are materialized locally (not iCloud-dataless).
- No `Image load failed` warning in the app's log; ImageIO decode activity is present.
- `com.apple.security.network.client` is granted, so remote images are not blocked by the sandbox.

## Root Cause (of the systemic failure found instead)

Noto renders an image **only when the entire paragraph is exactly one image link**.

`MarkdownBlockKind.detect` (`Noto/Editor/TextKit2EditorView.swift:437`) strips leading
spaces only, then `MarkdownImageLinkParser.parse` anchors on
`^\s*(!)?\[([^\]]*)\]\(([^)]+)\)\s*$` (`TextKit2EditorView.swift:163`). The balanced-bracket
fallback (`extractBalancedLinkParts`, line 213) also requires everything after the closing
`)` to be whitespace.

So any of these make the line fall back to `.paragraph` and show as raw markdown:

- trailing caption text after `)` — e.g. `![Alt](url)Alt caption text`
- a blockquote prefix — `> ![](url)`
- a list prefix — `- ![](url)` or text with an inline image inside a bullet
- leading prose before `![`
- an alt text containing a newline (link split across lines)

### Vault-wide audit (script: `scratchpad/audit.py`)

587 image lines across the vault do not render:

| Count | Cause |
|---|---|
| 431 | trailing text after `)` |
| 65 | inside a blockquote (`> ` prefix) |
| 54 | inside a list item (`- ` prefix) |
| 31 | leading text before `![` |
| 4 | unclosed / multiline alt text |
| 2 | site-absolute path (`/public/assets/...`) — genuinely unresolvable, no origin stored |

Concentrated in `Captures/` (web clippings), which is where clipper output puts a caption
right after the image link.

Two further link shapes are unresolvable by design and produce no image:
- protocol-relative URLs, `//host/path.gif` — `resolving(relativeTo:)`
  (`TextKit2EditorView.swift:129`) splits on `/` with empty components preserved, the
  all-non-empty guard fails, and `URL(string:)` then has no scheme.
- site-absolute paths, `/public/...` — bail out on the `hasPrefix("/")` guard.

## Fix

Two changes in `Noto/Editor/TextKit2EditorView.swift`, both in shared (cross-platform) code:

1. **Balanced-parse fallback now handles `!`-prefixed links.** `extractBalancedLinkParts`
   previously required `hasPrefix("[")`, so `![…](…)` never reached it; and the fallback
   required an image file extension plus a scheme. It now accepts an optional `!` and
   reports it, and `parse` trusts an explicit `!` the same way the regex path already
   does. Fixes nested parentheses in the URL (`DMG_(Apple_Silicon)`) and extension-less
   badge/CDN endpoints. Non-`!` links still require an image-looking URL *and* a scheme,
   so ordinary links do not turn into gray placeholders.

2. **`MarkdownBlockKind.detect` retries after stripping blockquote/list markers.** New
   `MarkdownBlockMarker.stripping(from:)` drops up to three leading `> `/`- `/`* `/`+ `
   markers. The retry runs *only* for image detection and only after the plain parse
   failed, so todos, bullets, and dividers are untouched.

## Success Criteria

### 1. A lone image behind a blockquote or list marker renders
- [x] Verified in unit test
- [x] Verified in app

**Unit tests:** `NEW` — `NotoTests/TextKit2MarkdownLayoutTests.swift` →
`imagesBehindBlockquoteMarkerAreDetected`, `imagesBehindListMarkerAreDetected`,
`nestedBlockMarkersStillYieldAnImage`, and macOS
`webClippingImageShapesAreDetectedAndHidden`.

### 2. Image URLs with nested parentheses or no file extension render
- [x] Verified in unit test
- [x] Verified in app

**Unit tests:** `NEW` — `imageURLsWithNestedParenthesesAreDetected`,
`explicitImagePrefixIsTrustedWithoutFileExtension`.

### 3. No regression: ordinary links, todos, bullets, dividers keep their kinds
- [x] Verified in unit test
- [x] Verified in app

**Unit tests:** `NEW` — `extensionlessLinksWithoutImagePrefixStayParagraphs`,
`todoMarkersSurviveMarkerStripping`, `bulletsWithOrdinaryLinksStayBullets`,
`dividersAreUnaffectedByMarkerStripping`. `EXISTING` — `nonImageEmptyLinksStayRegularParagraphs`,
`bareTodoSyntaxStaysRawUntilTrailingSpace`, `threeDashLinesAreDetectedAsDividerBlocks`.

**App verification (all three criteria):** a temp note carrying all four fixed shapes plus
both negative controls was opened in a Debug build of the macOS app — evidence
`scratchpad/verify-fix.png` (blockquote image + list-marker image render) and
`scratchpad/verify-fix2.png` (nested-paren badge + extension-less badge render; `- [Clicked](…)`
still a bullet hyperlink; `- [ ] ` still a checkbox). Temp note deleted afterwards.

### Regression run

Full macOS suite, `flowdeck test -s Noto-macOS -D "My Mac"`:

- With the fix: 229 passed / 10 failed
- Source reverted to pre-session baseline (tests kept): 229 passed / 9 failed — 8 pre-existing
  failures plus the new macOS image test correctly failing without the fix

The 8 stable pre-existing failures (`OwnershipDependencyTests` ×2,
`OwnershipRearchitecturePhase0BaselineTests`, `SearchIndexControllerTests` ×3,
`TagControllerTests`, `TextKit2EditorLifecycleMacTests/pageMentionSuggestionRows…`) are
unrelated to image parsing and predate this change. `NoteEditorSessionTests` ×2 (12 s
debounce timeouts) appeared in one run and not the other — flaky, not caused by this change.

A true clean-tree baseline is not obtainable: stashing `TextKit2EditorView.swift` breaks the
build because other uncommitted work (`NotoTests/TodoMarkerRendererTests.swift`) depends on
`TodoMarkerRenderer`, which lives in the working-tree version of that file.

## Remaining Work

512 image lines still do not render. Measured with `scratchpad/audit.py` before and after:
585 → 512.

| Count | Shape | Cost |
|---|---|---|
| 363 | caption text after the image — `![Alt](url)Alt caption` | needs layout work: one paragraph must show an image *and* a text line |
| 81 | `[![](img-url)](link-url)` — a link wrapping an image | **cheap** — when the alt text is itself an image link, render the inner image |
| 68 | prose before an inline image mid-sentence | needs layout work, same as the caption case |

The 81-line nested case is the obvious next step and is a parser-only change.

**Side effect worth deciding on:** small badge images now render, and the existing sizing
rule scales every image to the full container width — so a 20px-tall shields.io badge is
blown up to ~560pt wide (visible in `scratchpad/verify-fix2.png`). This is pre-existing
behaviour for all images, newly visible for badges. Capping display at the image's intrinsic
size would fix it.

## Investigation Log

### Attempt 1 — reproduce the cited note

**Hypothesis:** the local `.attachments/` path fails to resolve or read on macOS.
**Checks:** standalone Swift probe of `resolving(relativeTo:)` + `NSFileCoordinator` read;
iCloud materialization check; app entitlements; runtime log capture; axdriver-driven
open of the note in both the installed and a freshly built app at two window widths.
**Result:** all pass — the image renders. Not reproduced.

### Attempt 2 — audit every image link in the vault against the parser rules

**Hypothesis:** "some images" refers to a class of link shapes, not that one note.
**Method:** reimplemented `MarkdownImageLinkParser.parse` + `MarkdownImageLink.resolving`
in Python and ran it over every `.md` in the vault.
**Result:** 587 non-rendering image lines, dominated by "caption text trailing the link"
(431). This is a real, systemic bug and the most likely referent of the report.
