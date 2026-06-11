# Feature: image-links-no-label (bug fix)

## User Story

Image links with no alt label — `![](xyz.png)` and especially pasted attachments like `![](attachments/Pasted image 20260610.png)` — did not render as image blocks in the editor. They should render like any other image link.

## Root Causes (two distinct bugs)

1. **Parser rejected spaces in the URL.** `MarkdownImageLinkParser.linkRegex` used `([^)\s]+)` for the URL part, so any path containing a space (the default for pasted attachment filenames) failed to parse and the line stayed plain text.
2. **iOS image overlays never resolved vault-relative URLs.** `MarkdownSemanticAnalyzer.renderableBlocks` detects block kinds without a `vaultRootURL`, so the overlay `UIImageView` path got an `imageLink` whose `url` was `nil` for every vault-relative path. The TextKit delegate path (which has the vault root) loaded the file into the cache, but the overlay could not look it up — leaving a permanent gray placeholder. Remote `https` images worked, masking the bug.

## Fix

- Regex URL part `([^)\s]+)` → `([^)]+)`; markdown title suffix (`url "title"` / `url 'title'`) is stripped from the captured URL (`strippingTitle(from:)`).
- iOS `imageLink(in block:)` now returns `link.resolving(relativeTo: vaultRootURL)`, and `refreshImageOverlayViews` uses that helper instead of pattern-matching the unresolved kind.
- Added an `os_log` warning when an image load fails (url, isFileURL, file-exists) — this is what isolated bug #2.

## Success Criteria

- SC1: `![](xyz.png)` renders as an image block (placeholder if file missing). ✅ simulator-verified
- SC2: `![](attachments/Pasted image 20260610.png)` with the file present renders the actual image. ✅ simulator-verified (iPhone, cold launch)
- SC3: `![](url "title")` parses with the title stripped. ✅ unit test
- SC4: Non-image empty links (`[](https://…/article)`) still render as plain paragraphs. ✅ existing test passes

## Tests

- `NotoTests/TextKit2MarkdownLayoutTests.swift`
  - `noLabelImageLinksWithSpacesInPathAreDetected` — SC2 (parse + vault resolution)
  - `noLabelImageLinksWithBareFilenameAreDetected` — SC1
  - `markdownTitleAfterImageURLIsStripped` — SC3
- Suite result: 92 passed; the only failures (`dividerMarkdownHidesUntilSelected`, `deletingRenderedHyperlinkCanRevealFullMarkdownSyntax`) were verified to fail identically at clean HEAD — pre-existing, unrelated.

## Residual Risks

- macOS draws images through the (already-resolved) layout-fragment path and compiles clean, but macOS rendering of vault-relative images was not visually re-verified in this session.
