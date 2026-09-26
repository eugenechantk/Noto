# iOS Visual Evidence Audit

Verdict: PASS

Timestamp: 2026-09-26 00:05 HKT

Repository: /Users/eugenechan/dev/personal/Noto

Simulator: iPhone 17, iOS 26.3, 7FE84808-DCA6-4AF5-9089-DBD8172FF34A

App: Noto2 / com.eugenechan.Noto2

## Change Audited

Media search now matches full source-note content, frontmatter, link URLs, and saved link-preview metadata while preserving source-note isolation, type filters, and navigation state.

## Success Criteria

| Criterion | Result | Evidence |
| --- | --- | --- |
| Body-only terms find every media item from the matching note without leaking to another note that references the same file | PASS | `01-baseline-four-items.png` shows Ocean study and Unrelated sharing `coast.jpg`. `02-body-search-two-results.png` shows `bioluminescence` returns only Ocean study image and video (2), excluding Unrelated. |
| Type filters combine with content search and navigation preserves query/filter state | PASS | `03-body-search-video-filter.png` narrows the body match to the one video. `04-ocean-source-note.png` proves exact Ocean source routing. `05-back-preserves-body-video.png` retains both `bioluminescence` and Videos. |
| Frontmatter-only terms find all media from the source note | PASS | `10-frontmatter-search-two-results.png` shows `Adrienne`, present only in Ocean study frontmatter, returning its image and video (2). |
| Expired saved preview title/summary metadata remains searchable offline and isolated to its note | PASS | The deliberately expired cache was installed before launch. `06-expired-metadata-search-one-result.png` shows title-only `botanical` returns only Field journal. `07-field-journal-source-note.png` proves exact source routing and shows the invalid domain has already failed to refresh with `Preview unavailable`. `08-back-preserves-expired-metadata-query.png` proves the cached result and query survive that failed refresh. `09-summary-metadata-after-failed-refresh.png` shows summary-only `woodland` still returns Field journal. |
| All query terms may match across note and metadata fields | PASS | `13-split-field-all-term-search.png` shows `botanical journal`, split between cached preview title and note title, returns Field journal (1). |
| Empty and clear behavior remains correct | PASS | `11-no-result-state.png` shows a zero-result query and empty state. `12-clear-restores-four.png` shows Clear restores all four fixture tiles. |
| Search performs no per-keystroke parsing or network fetching; reloads replace stale content and preview notifications refresh without clearing state | PASS by source/test evidence | `VaultMediaLibrary` stores one normalized note projection per note during the detached scan and filters that projection in memory. `LinkPreviewCache.searchText(for:)` performs cache reads only. `MediaBoardScreen` injects the cache provider into its detached scan and refreshes on preview notifications. The package evidence records NotoVault 113 tests and final NotoLinkPreview 54 tests passing, including expired/failed cache retention and edit replacement coverage. The failed invalid-domain preview followed by `08` and `09` also proves the live notification/refetch path retained query and saved search metadata. |

## Artifacts

- `01-baseline-four-items.png`: four-tile fixture baseline.
- `02-body-search-two-results.png`: body-only query returns Ocean image and video.
- `03-body-search-video-filter.png`: Videos narrows the same query to one.
- `04-ocean-source-note.png`: correct Ocean study source note.
- `05-back-preserves-body-video.png`: query and Videos filter preserved.
- `06-expired-metadata-search-one-result.png`: expired title metadata finds Field journal only.
- `07-field-journal-source-note.png`: exact Field journal source and failed invalid-domain preview.
- `08-back-preserves-expired-metadata-query.png`: title metadata and query survive failed refresh.
- `09-summary-metadata-after-failed-refresh.png`: expired summary metadata remains searchable.
- `10-frontmatter-search-two-results.png`: frontmatter-only author finds Ocean media.
- `11-no-result-state.png`, `12-clear-restores-four.png`: empty and clear states.
- `13-split-field-all-term-search.png`: all-term match across metadata and note title.
- `media-content-search-flow.mov` (155.72 seconds): recorded body search, Videos filter, source navigation, Back preservation, expired metadata search, failed preview refresh, and retained metadata query.

## Commands

- `flowdeck config get --json`
- `flowdeck run -w /Users/eugenechan/dev/personal/Noto/Noto.xcodeproj -s Noto2 -S 7FE84808-DCA6-4AF5-9089-DBD8172FF34A --json`
- `.maestro/seed-vault.sh 7FE84808-DCA6-4AF5-9089-DBD8172FF34A --source-vault /Users/eugenechan/dev/personal/Noto/.codex/evidence/20260925-media-content-search/fixture-vault --bundle-id com.eugenechan.Noto2 --initial-tab media`
- Copied the supplied preview-cache JSON fixtures into the seeded app container at `Library/Caches/LinkPreviews/` before launch.
- FlowDeck `session start`, `tap`, `type`, `screen`, and `record` commands, all with the explicit simulator UDID.
- `ffprobe` confirmed the recording decodes, with duration 155.72 seconds.

## Notes

- The final Noto2 build/run succeeded after a concurrent link-preview UI migration finished. The first attempt had failed on that unrelated, temporarily incomplete migration; no audit source files were changed.
- The Noto2 app test suite is unverified in this run: one FlowDeck test runner stopped returning results and the serial retry was stopped by the build guard after process monitoring timed out. No test assertion failure was reported. Direct build/run and the full recorded UI audit succeeded.
- Package evidence at `../20260925-media-content-search/verification-summary.json` records passing full runs for all 12 packages, including NotoVault 113, final NotoLinkPreview 54, and a full NotoSearch 129-test standalone rerun after an initial timing failure under concurrent load.
- No implementation files were edited by this auditor.
