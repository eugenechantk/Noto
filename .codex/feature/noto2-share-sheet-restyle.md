# Feature: Noto 2 share sheet restyle + rich link cards

## User Story

When I share a link to Noto 2, the confirmation sheet should feel finished: a clear "saved" moment, the link I saved shown as a real preview, and obvious ways to keep going or leave.

## User Flow

1. Share a link from any app → Noto 2.
2. The sheet shows, everything centre-aligned, the main content vertically centred:
   - an orange-accented circle with a tick (saved),
   - title **Link captured**,
   - a short paragraph: saved to the inbox as a quick capture (for X / Instagram: its photos and videos follow in a minute),
   - the link as a preview card (title, description, site, thumbnail; Safari's page title while the preview loads).
3. Pinned to the bottom: **Keep editing** (primary, orange) opens Noto 2 on that capture note; **Close** (secondary) below it dismisses the sheet.
4. The sheet also closes with the ✕ at the top right, or by swiping it down.
5. If nothing linkable was shared or saving failed: same layout with a warning icon, **Couldn't capture link**, the reason, and only **Close**.

## Success Criteria

1. **SC1** — Header: only a circular ✕ at the top right; no title in the header. Tapping it closes the sheet.
2. **SC2** — Main content is centre-aligned horizontally and vertically centred in the space above the buttons: icon, title, body, link card, in that order.
3. **SC3** — Icon: a circle with a tick, orange accents.
4. **SC4** — Title "Link captured"; body explains it was saved to the inbox (media variant for X / Instagram).
5. **SC5** — The link shows as a preview card like the editor's (title, subtitle, host, thumbnail when available). While loading, it shows the page title Safari gave us (or the host) with "Loading preview…"; if the fetch fails, the title/URL with "Preview unavailable".
6. **SC6** — Bottom buttons pinned to the bottom: primary "Keep editing" (opens Noto 2 on the capture note, as before), secondary "Close" below it (closes the sheet).
7. **SC7** — Swiping the sheet down closes Noto's sheet (iOS then shows the system share sheet again — system behaviour for extension sheets); the link capture is still filed the next time Noto 2 opens.
8. **SC8** — Failure state uses the same layout with a warning icon, "Couldn't capture link", the message, and only Close.
9. **SC9** — Capture behaviour is unchanged: staging, media job, deep link, filing into `inbox/`.
10. **SC10** (added 2026-09-26, Eugene: "og image and description … apply to all of the link capture cards regardless of the link") — every link card (editor iOS/macOS, Digest, share sheet) shows the page image as a full-width banner, the title, up to 3 lines of description, and the site; a page with no image gets a placeholder banner (site icon or link symbol + host). One fixed height (300 pt, same as an image line) so notes don't reflow while previews load.
11. **SC11** — Links that `LinkPresentation` barely describes (Instagram: title "Instagram", nothing else) get their title, description and image from the page's Open Graph tags; cards cached by the old fetcher are refreshed.

## Test Strategy

- SC5 (content rules): `NotoLinkPreview` package tests for `LinkPreviewCardContent.make(url:state:fallbackTitle:)`.
- SC9: existing `NotoShareCapture` package tests and `Noto2Tests` (capture routing, filing) must stay green.
- SC1–SC8 (layout, interaction, dismissal): simulator — Safari → Share → Noto 2, screenshots of the loading and loaded card, ✕ / Close / swipe-down / Keep editing, then independent `ios_visual_evidence_auditor` audit. Use a non-X/Instagram URL so no media job reaches the live queue.

## Tests

### Package — `Packages/NotoLinkPreview` (54)
- `LinkPreviewCardContentTests`: `fallbackTitleShowsWhileLoadingAndAfterFailure`, `fetchedTitleWinsOverFallbackAndBlankFallbackIsIgnored` — SC5
- `LinkPreviewCardLayoutTests`: `bannerOnTopTextBelow`, `cardMatchesAnImageLine`, `shortCardClampsTheBanner`, `zeroWidthIsSafe` — SC10
- `LinkPreviewOpenGraphTests` (8): attribute-order/entity/relative-URL parsing, Twitter/`<title>` fallbacks, non-web images, crawler UA + image download, no-tags error, strong primary used as is, weak primary takes OG title and fills gaps, failures — SC11
- `LinkPreviewCacheTests.olderFetcherGenerationIsRefetchedButStillSearchable` — SC11

### Package — `Packages/NotoShareCapture` 28/28 (unchanged) — SC9

## Implementation Details

- **Shared card** (`NotoLinkPreview/LinkPreviewCard.swift`): one SwiftUI view + `LinkPreviewCardStyle`; laid out to `LinkPreviewCardLayout` (banner 168 pt, total 300 pt, title ≤2 lines, description ≤3). The editor's `LinkPreviewCardView` (iOS `UIControl` / macOS `NSView`) now hosts it (`UIHostingController` with `safeAreaRegions = []`, `NSHostingView`) and keeps its tap / long-press handling; Digest hosts the same view; the share sheet uses it directly. The editor's reserved paragraph height follows `LinkPreviewCardLayout.defaultHeight`.
- **Richer metadata** (`LinkPreviewOpenGraph.swift`): `OpenGraphParser`, `OpenGraphFetcher` (crawler user agent `facebookexternalhit/1.1`, image downsampled to 640 px), `CompositeLinkPreviewFetcher` (LinkPresentation first; OG fills missing image/description; OG title preferred when LinkPresentation had neither). Used by the app (`LinkPreviewSupport`) and the extension.
- **Cache refresh**: `LinkPreviewMetadata.schemaVersion` (current 2; pre-versioning entries decode as 1 and read as expired, search text kept).
- **Share sheet** (`Noto2ShareExtension/ShareViewController.swift`): `LinkCapturedSheet` — native Liquid Glass ✕ (`.glassEffect(.regular.interactive(), in: .circle)`), centred content in a `ScrollView` with `minHeight` = available height (vertically centred, scrolls at large text sizes), orange tick badge with a bounce, title, message, `LinkPreviewCard`; `GlassEffectContainer` with `.glassProminent` Keep editing (orange tint) and `.glass` Close. `ShareLinkPreviewModel` (observes `LinkPreviewService.didChangeNotification`), `ShareLinkPreviews.service` (extension's own cache). The extension target now links `NotoLinkPreview` (pbxproj).
- **Swipe down**: the host owns the extension's sheet, so no presentation delegate fires; `viewDidDisappear` ends the request instead. iOS still returns to the system share sheet after a swipe (system behaviour for extension sheets); ✕ and Close dismiss everything.

Success criteria: SC1 ✔ SC2 ✔ SC3 ✔ SC4 ✔ SC5 ✔ SC6 ✔ (after bug 036) SC7 ✔ SC8 ✔ SC9 ✔ SC10 ✔ (iOS; macOS compiles) SC11 ✔

## Evidence

- Simulator self-check: `.codex/evidence/20260926-share-sheet-and-link-cards/` (sheet loading/loaded, editor cards incl. Instagram and placeholder, Digest card).
- Independent audit 1 **PARTIAL**: `.codex/evidence/20260926-015825-ios-visual-audit/evidence.md` — SC1–SC5, SC7–SC11 PASS (content centred at x = 201.0, 300 pt cards with 168 pt banners, no reflow when previews load, Instagram real title/description/image on a fresh fetch, failure state via shared plain text). SC6 PARTIAL: Keep editing opened Digest on 1 of 3 cold launches → bug 036.
- Bug 036 fixed; independent re-audit **PASS**: `.codex/evidence/20260926-023946-ios-visual-audit/evidence.md` — Keep editing opened the note on 6/6 cold runs and a warm run; ✕, Close, swipe down, and filing (15 shares → 15 notes) still pass.
- Tests: `Noto2Tests` 114/114 before the fix, `SharedCaptureDrainQueueTests` 4/4 after; `TextKit2MarkdownLayoutTests` only the 4 known pre-existing failures; Noto-macOS compiles; packages 54/28/29.

## Residual Risks

- The X / Instagram "photos and videos" message variant and the "Preview unavailable" state were not exercised in the audit (social links must not be shared from the simulator; the failure state needs the network cut).
- macOS link card not exercised at runtime (compiles; local macOS runs are blocked by signing).
- Swiping the sheet down returns to the system share sheet rather than dismissing everything — an iOS limitation for share extensions.

## Bugs

- **036 — Keep editing sometimes opened Digest on a cold launch** (audit 1, pre-existing race): three launch-time triggers ran `drainSharedCaptures()` concurrently and a pass that had not recorded the capture consumed the open request. Fixed with `Noto2/SharedCaptureDrainQueue.swift` (one pass at a time, coalesced follow-up pass, request resolved after the queue settles). See `bug-reports/036-keep-editing-cold-launch-opens-digest.md`.
