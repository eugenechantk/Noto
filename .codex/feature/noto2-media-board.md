# Feature: Noto 2 media board

## User Story
Browse saved and extracted multimedia across the vault visually, then open its source note.

## User Flow
Media joins Capture, Digest, Search, and Browse as a dedicated Noto 2 tab. A Pinterest-inspired masonry board shows rounded thumbnails with source-note captions, newest edited notes first. Search matches note titles, paths, media captions, full source-note content, saved frontmatter, and saved link metadata (see `noto2-media-content-search.md`). A compact toolbar title matches Browse, and a toolbar Search button opens a dedicated search view. File-type controls were removed by the follow-up in `noto2-media-search-navigation.md`. Tap a tile to push its source note inside Media; Back restores the board or search results.

## Success Criteria
1. Discover media references recursively across notes, including Hermes `.attachments/` images/videos, remote images, and linked audio/PDFs. Deduplicate repeated references within a note while preserving distinct source notes. Exclude code examples and unsafe local paths.
2. Lazy, adaptive columns on iPhone/iPad; real image ratios, video posters, accessible type placeholders for unavailable media. No autoplay.
3. Every card opens the correct source note using existing editor navigation; Back preserves board state.
4. Dedicated search, loading/empty/error states, pull to refresh, and refresh on note/file/foreground changes.
5. Discovery and thumbnail work stay off the main thread and media scanning starts only when the tab appears.

## Design Reference
Mobbin Pinterest boards: https://mobbin.com/screens/7fe263bf-7efe-4077-b881-c280dc960fec and https://mobbin.com/screens/d2659fae-b5ba-4b0c-b4d8-41530a847350. Observed rounded cards, tightly spaced independent columns, varied image heights, and short captions. Keep native Noto colors/navigation.

## Test Strategy
Swift Testing in NotoVault covers extraction, path safety, source association, deduplication, filtering, ordering, and real filesystem refresh after edits/moves/deletions. Build Noto2 and independently audit simulator board, filters, note navigation, and Back with screenshots and recording.

## Tests
`Packages/NotoVault/Tests/NotoVaultTests/VaultMediaLibraryTests.swift` contains nine tests covering classification/source paths, code/frontmatter exclusion and unsafe paths, per-note deduplication, angle/title/parenthesis syntax, type/text filtering, real filesystem edit/move/delete sequences, symlink escapes, stable UUID identity after rename, empty vaults, unreadable-note reporting, and readable captions for shared-link titles.

`Noto2Tests/Noto2StartupTests.swift` verifies Media requires the deferred vault workspace while Capture still launches without it.

All 12 packages passed (533 tests), including the full NotoVault suite (110). Full Noto2 simulator suite passed (113 tests). Logs and machine-readable summary: `.codex/evidence/20260925-media-board/verification-summary.json`.

## Implementation Details
NotoVault owns read-only discovery and media models. Noto2/Media owns SwiftUI presentation and Apple thumbnail rendering. Existing BrowseDestination resolves editors within a separate Media navigation stack. Cards use stable identities, lazy columns, native Dynamic Type, type badges, accessible labels/identifiers, and a bounded 48 MB thumbnail cache. Local images are downsampled from coordinated file URLs rather than loading full-resolution pixel buffers. Remote video/PDF references show lightweight type placeholders; remote images are downloaded to temporary files and downsampled. Audio uses a waveform tile. No media autoplays.

## Residual Risks
Independent iPhone visual audit: **PASS**. Report: `.codex/evidence/20260925-232120-ios-visual-audit/evidence.md`. Final build proves masonry rendering, search/type filters, exact source-note routing (including an image shared between notes), Back-state preservation, video/PDF previews, missing-preview navigation, scrolling, and pull-refresh discovering an external PDF addition. Two decoded recordings capture complete flows.

iPad runtime remains visually unverified because the session's simulator isolation assigned an iPhone. Media still downloading from iCloud remains visible with a fallback; unreadable notes are reported as pending rather than silently treated as an empty vault. The board recognizes inline markdown media links used by Noto and Hermes; reference-style markdown and HTML embeds are not currently extracted. Live iCloud download timing, remote-provider availability, and forced loading/error banners are not proven by local fixtures. Unrelated concurrent Browse, link-preview, and project-file edits were preserved; the visual audit rebuilt the current shared workspace.

## Bugs
None yet.
