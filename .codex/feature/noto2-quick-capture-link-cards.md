# Feature: Noto 2 quick capture — link cards

## User Story

As a Noto 2 user, when a quick capture is a link (a share-sheet capture, or a URL I typed into Capture), I want it to show the same rich preview card the editor shows for links — in the Capture editor, in the note I land on from **Keep editing**, and on the Digest card — rather than a raw `[title](url)` or `https://…` string.

## User Flow

1. Share a page to Noto 2 (body `[Page title](https://…)`) or type a bare URL in Capture.
2. The Capture editor renders the line as a link card as soon as the caret leaves it (loading → title/description/thumbnail).
3. **Keep editing** opens the filed note in Browse: the same card, with the raw markdown revealed when the caret is on that line.
4. The Digest card shows the link as a card above any remaining text; tapping the card opens the link.

## Prerequisite

The editor's link cards were built on branch `worktree-link-preview-cards` (package `NotoLinkPreview`, `MarkdownBlockKind.linkPreview`, `LinkPreviewCardView`) and never merged. This task lands that work on `main` first (source files only — the branch also carries unrelated deletions of old evidence folders that are not brought over), then extends it.

## Success Criteria

1. **SC1 — markdown-link lines are preview blocks.** A paragraph that is exactly one `[title](url)` markdown link with an `http(s)` URL (optional indent/trailing whitespace) is detected as a link-preview block, alongside bare-URL lines. Lines with text around the link, image links `![](url)`, and non-web schemes are still not.
2. **SC2 — editor renders the capture as a card.** In Noto 2's Capture editor and in the note opened from Keep editing, a share-sheet capture body renders as a card; placing the caret on the line reveals the raw `[title](url)` text.
3. **SC3 — Digest card shows a link card.** When a capture's body starts with a link-preview line, the Digest card renders a link card for it (title/description/host/thumbnail via `LinkPreviewService`, loading and failed states included) followed by the remaining body text, and tapping the card opens the URL. Bodies with no link line render as before.
4. **SC4 — nothing else regresses.** Existing editor, digest and share-extension tests keep passing; the `NotoLinkPreview` package tests keep passing with the detector change.

## Test Strategy

- SC1: package unit tests on `LinkPreviewDetector` (new cases, one existing negative flipped).
- SC3 (pure part): app unit tests on `DigestLinkCardSplit` — the body → (url, remainder) split — in `Noto2Tests`.
- SC2/SC3 (rendering): simulator visual audit.

## Tests

### Package Unit — `Packages/NotoLinkPreview/Tests/NotoLinkPreviewTests/LinkPreviewDetectorTests.swift`
- `markdownLinkLineIsDetected` — SC1 (replaces `markdownLinkIsNotDetected`)
- `markdownLinkWithParenthesesInURLIsDetected` — SC1 (share extension percent-encodes `(`/`)`)
- `markdownLinkWithSurroundingTextIsNotDetected` — SC1
- `markdownLinkToNonWebURLIsNotDetected` — SC1

### App Unit — `Noto2Tests/DigestLinkCardSplitTests.swift`
- `bodyThatIsOnlyALinkSplitsToURLAndNoRemainder` — SC3
- `bareURLBodyAlsoSplits` — SC3
- `linkFollowedByTextKeepsTheText` — SC3
- `bodyWithoutLeadingLinkDoesNotSplit` — SC3

## Implementation Details

- **Landed the link-preview branch on `main`**: `Packages/NotoLinkPreview` (copied, `.build` dropped), `NotoShared/Editor/LinkPreviewCardView.swift` + `LinkPreviewSupport.swift`, the `TextKit2EditorView.swift` / `NotoTests` diffs applied with `git apply`, `.codex/feature/link-preview-cards.md`. The package is linked into Noto, Noto2 and Noto2Tests (pbxproj ids `B70000000000000000000030–36`). The branch's 500+ deletions of `.codex/evidence` files were **not** taken.
- **Detector** (`LinkPreviewDetector.url(inLine:)`): a trimmed line that is exactly `[title](destination)` now resolves to `destination` before the existing bare-URL rules run (`markdownLinkDestination(in:)`: no `]` in the title, no `)`/whitespace in the destination, `![…]` excluded by the leading `[`). Everything downstream — `MarkdownBlockKind.detect` → `.linkPreview`, the reserved-height paragraph, caret reveal, the overlay card — is unchanged, so the Capture editor and the note behind Keep editing card automatically.
- **Digest** (`Noto2/Digest/DigestLinkCard.swift`): `DigestLinkCardSplit.split(body:)` (pure) and `DigestLinkCard`, a `UIViewRepresentable` around the editor's `LinkPreviewCardView` fed by `LinkPreviewSupport.service`, re-configured on `LinkPreviewService.didChangeNotification` for its URL; tap opens the URL. `DigestScreen` shows card + remainder text when the split succeeds, the plain body otherwise.
- **Editor test** `urlsInsideProseStayParagraphs` now expects a lone `[Example](https://example.com)` line to be `.linkPreview` (the product decision this feature makes).

## Verification

- `Packages/NotoLinkPreview` `swift test`: 41/41 (was 38; 4 detector cases changed/added).
- `Noto2Tests` on `cc-56c91326` (iPhone 17 Pro, iOS 26.5): 96/96.
- `NotoTests/TextKit2MarkdownLayoutTests`: 60/64 — the 4 failures are the pre-existing ones documented on the link-preview branch (two wiki-link tests for an unshipped feature, two `AppTheme.uiPrimaryText` vs `NotoTheme.uiInk` theme-drift assertions). Two image-guard tests were updated to expect a card instead of a paragraph.
- Manual, 2026-09-20: share "Rust syntax" from Safari → Keep editing → editor shows the card (title, favicon, host, thumbnail); Digest tab shows the same card on the capture with the share-time stamp.
- Independent visual audit **PASS**: `.codex/evidence/20260920-205955-ios-visual-audit/evidence.md` (fresh build on its own sim). Capture tab: bare URL + Return → loading → loaded card, caret on line 2; long-press / arrow keys reveal the raw URL and the card returns when the caret leaves. Keep editing: `[title](url)` card, raw markdown revealed on the line. Digest: link card with remainder text below; left-swipe snooze and right-swipe Add-to both start from the card surface; a plain-text capture stays plain.

Success criteria: SC1 ✔ SC2 ✔ SC3 ✔ SC4 ✔

## Residual Risks

- The editor cards' own residual risks carry over unchanged (no setting to disable previews; macOS card never run; fixed 104pt height): see `link-preview-cards.md`.
- The Digest card fetches metadata when it appears, like the editor does — one network request per new URL, then cache.
- Tapping the Digest link card opens Safari; the swipe gestures still start from the card surface because the card is a `UIControl` — verified by the audit only, not by tests.

## Follow-ups (from the audit, not blocking)

- With the caret on the empty line right after a card, the caret draws roughly card-height tall — the trailing paragraph seems to inherit the 104 pt reserved line height. Editor issue inherited from the link-preview branch; worth a fix there.
- FlowDeck's typing auto-capitalised the scheme (`HTTPS://…`); the detector accepts it (scheme check is case-insensitive) and the card renders. Intended.

## Bugs

_None._
