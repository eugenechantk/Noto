# Feature: Media search across note content and link metadata

## User Story
Find multimedia by what its source note says and what its links describe, even when those words are absent from the card title or filename.

## User Flow
Use the existing Media search field and type filters. Search matches source-note body, saved frontmatter (including author/source fields), link text/URLs, and saved preview metadata (title, summary, host, URL). Terms can match across fields. Opening a result still opens its exact source note.

## Success Criteria
1. Body-only and frontmatter-only terms find all media from the matching note, with case/diacritic-insensitive all-term matching and type filters retained.
2. Link-metadata-only terms match media from the note referencing that link; unrelated notes do not inherit matches.
3. Cached previews remain searchable offline even after their display refresh TTL expires; missing/failed metadata does not hide body matches. Search initiates no network requests.
4. Note reloads replace removed content, and preview-service notifications refresh search metadata without clearing query/filter state.
5. Parsing and cache reads happen during the existing background scan, not per keystroke; normalized shared note search text is reused by media items.

## Test Strategy
NotoVault regression tests cover body/frontmatter/URL/preview search, split-field terms, source isolation, filters, and edit refresh. NotoLinkPreview tests cover title/summary/host/URL cache text, expired successes, and failed/missing entries. Full relevant package suites and Noto2 app tests, followed by independent recorded simulator checks of content-only and metadata-only results and source navigation.

## Implementation
NotoVault receives a Sendable URL-to-search-text provider, keeping vault logic independent of the preview package. Noto2 supplies its existing LinkPreviewCache and listens for preview changes. Only notes containing media read cached metadata. One normalized copy-on-write note string is reused across its media items. Saved note data remains filesystem-owned; the note search projection is in memory. The preview cache saves a tiny `.search.txt` projection of its last successful metadata alongside each cached preview, preserving offline matches through expiration or failed refresh. Successful new metadata replaces it; cache removal clears it.

## Verification
- Full NotoVault: 113 tests passed.
- Full NotoLinkPreview: 54 tests passed on the final rerun after concurrent preview changes, including retained text after expiry/failed refresh, updates replacing old text, and cache removal.
- Broader package sweep: all other packages passed except the existing NotoSearch debounce timing case on the first run; standalone full NotoSearch rerun passed all 129 tests. Both logs retained.
- All 12 packages have a passing full run: 557 package tests total (latest passing run for each package).
- Noto2 app suite could not complete: initial test runner stalled without results and was cancelled after five minutes; serial retry exited 75 when the build guard's process monitor timed out. No app-test pass is claimed. Logs retained under `.codex/evidence/20260925-media-content-search/`.
- Independent recorded iPhone 17 / iOS 26.3 audit passed: body-only, frontmatter-only, expired link-title/summary search, failed-refresh retention, mixed-field terms, exact source navigation, Back/query/filter preservation, no results, and clearing search. Final build/run passed. Evidence: `.codex/evidence/20260925-235406-ios-visual-audit/evidence.md` and its 155.72-second recording. iPad runtime was not verified in this audit.
- Guard was inspected (no remaining breaker, process monitor recovered); no guard bypass/reset or shared-process cleanup was performed.

## Residual Risks
Live providers may supply incomplete metadata. Only saved/available metadata is searched; the feature does not crawl links that have never produced a preview.
