# iOS Visual Evidence Audit

Verdict: PASS

Timestamp: 2026-09-25 23:29 HKT

Repository: /Users/eugenechan/dev/personal/Noto

Simulator: iPhone 17, iOS 26.3, 7FE84808-DCA6-4AF5-9089-DBD8172FF34A

App: Noto2 / com.eugenechan.Noto2

## Change Audited

Noto 2 Media tab: vault-wide media discovery, Pinterest-style masonry board, search and media-type filters, source-note navigation, state preservation, thumbnails/placeholders, and refresh behavior.

## Success Criteria

| Criterion | Result | Evidence |
| --- | --- | --- |
| Media appears together across notes and keeps distinct source-note associations | PASS | `10-final-board-after-rebuild.png` shows 11 image/video/audio/PDF items; `11-shared-title-source-note.png` proves the shared coast image opens the distinct `Shared post.md` note. The supplied 110-test NotoVault run is recorded in `../20260925-media-board/verification-summary.json`. |
| Pinterest-style adaptive masonry uses varied real ratios, readable captions and type badges, with placeholders for unavailable media | PASS on iPhone | `02-images-filter-hero.jpg`, `10-final-board-after-rebuild.png`, and `16-board-scrolled-middle.png` show independent columns, varied heights, rounded cards, readable captions, Video/Audio/PDF badges, and loaded content during a long scroll. `01-board-launch.jpg` shows the unavailable-image placeholder. No media autoplayed. |
| Every card opens the correct source note and Back preserves board state | PASS | `07-source-note-mountains.png` opens Mountain mornings; `08-back-preserves-search-filter.png` retains the Images filter and `mountain` query; `09-missing-source-note.png` opens the missing-preview source; `11-shared-title-source-note.png` and `13-pdf-source-note.png` prove shared-title and PDF source routing; `14-pdf-back-state.png` retains PDFs. |
| Search, filters, empty state, clear, pull refresh, and file-change refresh work | PASS | `03-video-filter.jpg`, `04-audio-filter.png`, and `12-pdf-filter-thumbnail.png` prove type filters. `05-search-no-results.png` proves the no-result state and clear affordance. `06-search-result-image-filter.png` proves combined search/filter. After externally adding a second PDF note while the app was running, pull-to-refresh changed PDFs from 1 to 2 in `15-external-pdf-after-pull-refresh.png`. |
| Local image/video/PDF previews render; missing media remains navigable | PASS | `03-video-filter.jpg` shows an extracted video poster, `12-pdf-filter-thumbnail.png` shows a rendered first PDF page, and `09-missing-source-note.png` proves a fallback card still opens its note. |
| Scanning and thumbnail work are deferred/off-main and starts only when Media is visible | PASS by source/test evidence | `MediaBoardScreen.swift` gates reload on `isVisible` and performs `VaultMediaLibrary.scan()` in a detached utility task. `MediaBoardTile.swift` loads thumbnails only from visible lazy tiles and dispatches rendering to detached utility work. The supplied verification summary records 110 NotoVault tests and 113 Noto2 tests passing. |

## Artifacts

- `01-board-launch.jpg` and `01-board-launch-tree.json`: initial nine-item board before final fixture additions.
- `02-images-filter-hero.jpg`: image-filter hero view with varied tile proportions.
- `03-video-filter.jpg`, `04-audio-filter.png`, `12-pdf-filter-thumbnail.png`: type-filter states.
- `05-search-no-results.png`, `06-search-result-image-filter.png`: search empty and matching states.
- `07-source-note-mountains.png`, `08-back-preserves-search-filter.png`, `09-missing-source-note.png`: source-note and state-preservation flow.
- `10-final-board-after-rebuild.png`: final binary showing readable `A beautiful place` caption and live PDF thumbnail.
- `11-shared-title-source-note.png`, `13-pdf-source-note.png`, `14-pdf-back-state.png`: final exact-note routing and Back behavior.
- `15-external-pdf-after-pull-refresh.png`: external addition discovered by pull refresh.
- `16-board-scrolled-middle.png`: long-board scrolling and lazy loaded thumbnails.
- `media-board-flow.mov` (123.08 seconds): initial filters, search, navigation, Back, and missing-preview flow.
- `final-caption-pdf-flow.mov` (82.45 seconds): final caption/PDF/navigation/refresh/scroll flow.

## Commands

- `flowdeck config get --json`
- `flowdeck run -w /Users/eugenechan/dev/personal/Noto/Noto.xcodeproj -s Noto2 -S 7FE84808-DCA6-4AF5-9089-DBD8172FF34A --json`
- `.maestro/seed-vault.sh 7FE84808-DCA6-4AF5-9089-DBD8172FF34A --source-vault /Users/eugenechan/dev/personal/Noto/.codex/evidence/20260925-media-board/fixture-vault --bundle-id com.eugenechan.Noto2 --initial-tab media`
- `flowdeck ui simulator session start -S 7FE84808-DCA6-4AF5-9089-DBD8172FF34A --json`
- FlowDeck `tap`, `type`, `swipe`, `screen`, and `record` commands, all with the explicit simulator UDID.
- `ffprobe` confirmed both recordings decode and have durations of 123.08 and 82.45 seconds.

## Notes

- No card clipping or text collisions were observed on iPhone. The partially visible PDFs chip at the right edge correctly communicates that the native filter row scrolls horizontally.
- iPad was not run because the repository's single-simulator isolation assigned this audit to the iPhone simulator; the guard was not bypassed. The implementation computes column count from available width, but iPad layout remains visually unverified.
- Loading and failure banners were not artificially induced. Their implementations and accessibility identifiers were inspected in `MediaBoardScreen.swift`; normal load, empty, filtered-empty, unavailable-preview, and live refresh states were exercised.
- The final rebuild included unrelated concurrent Browse, link-preview, and project-file edits already present in the shared working tree. This audit changed no implementation files.
