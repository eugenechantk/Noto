# Feature: Noto 2 — independent three-screen capture/search/browse app

Plan: `.claude/brainstorm/noto2-app-plan.md`. Tier: product.

## User Story

As Eugene, I want a second, separate iOS app ("Noto 2") on my phone that does exactly three things against my Noto vault — jot a thought and file it, search everything and get an LLM summary of the hits, and browse/open notes — reusing Noto's editor, storage and search rather than rebuilding them.

## User Flow

1. First launch → pick the vault folder (same picker as Noto; points at the iCloud `Brain/` or `Noto/` folder). Own bookmark, own sandbox, own search index.
2. **Capture** tab (start screen): full-screen markdown editor (TextKit 2). Type. Tap **Send** → file written to `inbox/<YYYY-MM-DD>-<sha8>.md` with frontmatter `id`, `created`, `updated`, `type: note`, `status: inbox`. Editor clears, a footnote status line shows the path for 1.5 s, file is indexed.
3. **Search** tab: type a query → hybrid keyword ∪ semantic results (title + body) listed immediately; above the list a plain "Summary" paragraph streams an LLM summary of the top hits. Tap a result → opens that note in the editor. ••• menu → OpenRouter key sheet (key, base URL override, vault) / Rebuild index.
4. **Browse** tab: folder/file explorer from the vault root; folders drill down; notes open in the editor (same `EditorContentView` + `NoteEditorSession`, autosave).

## Success Criteria

- SC1 ✅ Capture writes `inbox/<date>-<hash8>.md`; hash8 = first 8 hex of SHA-256 of the normalized body; identical text on the same day → same path (idempotent); frontmatter has `id`, `created`, `updated` (Noto's key, not `modified`), `type: note`, `status: inbox`; body preserved verbatim.
- SC2 ✅ Empty/whitespace-only capture is rejected (Send disabled); after a successful send the editor is empty and the new file is scheduled into the search index.
- SC3 ✅ Search runs `HybridNoteSearch` (keyword + semantic, title and content) against Noto 2's own index and lists results with title, breadcrumb, snippet; empty query → no results; opening a result routes to the editor for that file.
- SC4 ✅ Summary streams over the top-N (≤8) result bodies (each truncated) via `OpenRouterClient.stream`; shows "needs key" state when no key; shows error text on failure; a new query cancels the previous stream.
- SC5 ✅ Browse lists folders then notes for the root and any subfolder, sorted folders-first then by title; tapping a note opens the editor; edits autosave to the file.
- SC6 ✅ Noto 2 is a separate app: own bundle id `com.eugenechan.Noto2`, own display name, own icon, own entitlements; builds and runs on an iOS 26 simulator; the existing Noto target still builds and its unit tests still pass after the shared-file move.
- SC7 ✅ Shared code physically lives in `NotoShared/` and is compiled into both targets; nothing under `Noto/Views` (except what was moved to `NotoShared/Views`) or `Noto/NotoApp.swift` is compiled into Noto 2.

## Test Strategy

Pure logic is pulled into small app-target types so Swift Testing can hit it without UI:
- `CaptureFilingService` (NotoShared): hash/slug/frontmatter/file write → temp-dir integration tests (SC1, SC2 logic).
- `SummaryPromptBuilder` (Noto2): top-N selection + truncation + prompt shape → unit tests (SC4 logic).
- `ExplorerSorting` (Noto2): folders-first/title ordering → unit test (SC5 logic).
- Search (SC3): exercised by existing `NotoSearch` tests; Noto 2 adds an integration test that indexes a temp vault and runs `HybridNoteSearch` through the same call the screen uses.
- SC6/SC7: proven by `flowdeck build` of both targets + `NotoTests` run + simulator audit.

## Tests

All run on the session simulator via `flowdeck test -s Noto2 -S <udid>`; **21/21 pass** (2026-08-24, after the audit-round fixes).

### Noto2Tests (app target, Swift Testing)
- `Noto2Tests/CaptureFilingServiceTests.swift` — SC1, SC2
  - `slugIsDateAndSha8`, `frontmatterHasRequiredKeys`, `writesFileUnderInbox`, `sameBodySameDayIsIdempotent`, `whitespaceBodyIsRejected`, `normalizationIgnoresLineEndingsAndOuterWhitespace`
- `Noto2Tests/SummaryPromptBuilderTests.swift` — SC4
  - `takesTopNDistinctNotesAndTruncates`, `emptyResultsProducesNoPrompt`, `messagesCarryQueryTitlesAndBodies`, `unreadableFilesAreSkipped`, `renderedStripsMarkdownAsterisksAndBullets`
- `Noto2Tests/ExplorerSortingTests.swift` — SC5
  - `foldersFirstThenTitle`, `untitledNotesFallBackToFilename`
- `Noto2Tests/SnippetEmphasisTests.swift` — SC3 (brief §2.2: matched term emphasized)
  - `tokensDedupeAndDropShortWords`, `segmentsEmphasizeMatchesCaseInsensitively`, `noTokensLeavesSnippetPlain`, `overlappingTokensPreferLongest`, `stemsMatchSingularAndPlural`
- `Noto2Tests/SearchIntegrationTests.swift` — SC3, SC1
  - `hybridSearchFindsTitleAndBodyHits` (real temp vault through `SearchIndexController.shared.rebuildIndex` + `HybridNoteSearch.run` with the screen's request), `dedupedByNoteKeepsFirstRowPerNote`, `requestCarriesSemanticGate`

### Package (NotoSearch)
- `HybridRelativeGapTests` (`relativeGapKeepsHitsNearTheBest`, `relativeGapOnEmptyIsEmpty`, `peakTestSeparatesFlatFromPeaked`) — the new `semanticMinScore` / `semanticRelativeGap` / `semanticPeakMargin` request fields; full `swift test` 124 tests pass (one pre-existing timing flake in `SearchIndexCoordinatorTests` passes in isolation).

### Regression (SC6)
- `flowdeck test -s Noto-iOS` (all NotoTests): 301/313. The 10 deterministic failures (`OwnershipDependencyTests` ×2, `SearchIndexControllerTests` ×3, `TagControllerTests.savePreservesOriginalCreatedAt`, `EditorFindTests.textKitControllerHighlightsAndNavigatesMatches`, `TextKit2EditorLifecycleTests.pageMentionSuggestionRows…`, `TextKit2MarkdownLayoutTests` ×2) were **re-run on a baseline copy of the repo with only this work reverted and fail identically** — they come from the pre-existing uncommitted work in the tree (tags/deep-links/editor), not from the `NotoShared/` move. The other 2 from the first full run (`editorInteractionBaseline`, `legacyLastTurnFallsBackToFrontmatterSources`) passed in isolation (load flakes).
- `flowdeck build -s Noto-iOS` passes after the move.

## Implementation Details

- **Shared layer:** `git mv` of 32 files from `Noto/` into `NotoShared/{Editor,Storage,Search,Support,Chat,Views}`; both targets list the synced group. Coupling check: the only reference from the shared set into `Noto/` is `NotoCommandTarget`, which is `#if os(macOS)`-guarded so it compiles out of the iOS-only Noto 2. Docs updated: `README.md` (new "Two app targets" section), `CLAUDE.md` (app-target tree + editor-path note).
- **Project:** `Noto.xcodeproj/project.pbxproj` patched programmatically (IDs `A2…`): `Noto2` app target (iOS only, iOS 26, Automatic signing, team 39GJBP8V5A, `Noto2/Noto2.entitlements` (empty dict — the place for iCloud later), `Noto2Icon.icon`, display name "Noto 2", `ReadwiseSecrets.xcconfig` base config so the gitignored `LocalSecrets.xcconfig` key reaches the copied "Generate Secrets" phase), `Noto2Tests` unit-test target hosted by Noto2, package products NotoVault/NotoTags/NotoSearch/NotoChat/NotoEmbedding; shared scheme `Noto2.xcscheme`.
- **Chrome color + keyboard toolbar (2026-08-24, Eugene's feedback):** Noto 2's editor screens now use the editor's own `NotoTheme.background` (#0E1116) end-to-end (Capture container/footer/nav bar, Browse's NoteScreen) instead of `AppTheme.background`, killing the black-bars-vs-gray-editor split. The shared keyboard accessory gained an opt-in `EditorKeyboardToolbarStyle.floating`: an iOS 26 `UIGlassEffect` pill (44 pt, continuous corners, host chrome cleared per the liquid-glass skill) floating above the keyboard; `.docked` (default) keeps Noto's full-width #1A1C22 bar pixel-identical (hairline, 56 pt intrinsic). `EditorContentView` forwards the style; Noto 2 passes `.floating` on both screens. Verified with the software keyboard on the simulator (`kb-00c.png` in the session scratchpad); Noto-iOS rebuilt clean.
- **Capture card v2 (2026-08-24, Eugene's follow-up):** the card no longer fills the screen — ~70% of the space between the bars (clamped 240–460 pt), centered with clear air above and below so there is always room to swipe; 16 pt side margins and 12 pt inner padding around the editor. The top ✓ button is gone — the swipe IS the send (a "Swipe up to file" hint appears under the card when the draft is non-empty; ✕ discard remains). The drag gesture moved to the whole screen (`contentShape` + `simultaneousGesture` on the container), so the swipe works from the gaps even when a long note makes the editor consume in-card pans for scrolling. Verified on-simulator: multi-line markdown draft (heading, bold, bullets, numbered list) renders in-card via the shared editor, overflows and scrolls inside the card, and a gap-swipe filed the full note verbatim (`inbox/2026-08-24-a347e1d0.md`) with the card resetting to empty. Tooling: seed script gained `--draft-file` (writes `noto2.capture.draft` via defaults — direct plist edits are invisible to cfprefsd).
- **Capture card + swipe-to-send (2026-08-24, Eugene's request, modeled on Avec — spottedinprod.com/apps/avec/748, clip frames pulled and verified):** the draft lives on a rounded card (`NotoTheme.card`, continuous 24 pt corners, hairline border) on the unified background. Swiping the card up past 110 pt (or a flick with predicted travel > 320 pt) tilts it (≤5°, bottom anchor), fades in an orange "✓ Filed" overlay, flies it off the top, files the note, and springs a fresh card in from below (scale 0.94, 44 pt offset). The ✓ button triggers the same fly-off. Below threshold it springs back; swiping an empty card gives a warning haptic. The editor gained `backgroundColorOverride` (card paint) and `disablesScrollBounce` (bounce off, so short-draft pans reach the card's `simultaneousGesture`; long drafts scroll normally and ✓ still sends). Verified 3× on-simulator via idb (two swipes + one tick — file on disk each time, card resets, process stays alive).
- **Capture** (`Noto2/Capture/CaptureScreen.swift` + `NotoShared/Storage/CaptureFilingService.swift`): full-bleed `TextKit2EditorView` bound to an `@AppStorage` draft (survives kills); edits mirrored through `onTextChange` because the iOS editor only flushes the binding on resign; clearing bumps `documentID` so the editor reloads under an active keyboard. Top-right filled orange ✓ circle (kept top-right by Eugene's call: it must stay visible above the keyboard), ✕ discard with confirmation >200 chars, one-line placeholder (editor-managed: a UILabel inside `TextKit2EditorView` toggled synchronously in `textViewDidChange`/`applyText` via the `placeholder:` param — a SwiftUI overlay driven by the debounced `onTextChange` mirror desynced on device and let typed text overlap it), footnote status line in `safeAreaInset(.bottom)` for 1.5 s, word count ≥20 words, haptics. Filing = `inbox/<local-date>-<sha8>.md` with `id/created/updated/type: note/status: inbox` + blank line + body; coordinated write; idempotent per day; then `SearchIndexController.shared.scheduleRefreshFile`.
- **Search** (`Noto2/Search/`): `SearchModel` (@Observable, debounced 220 ms, cancels in-flight search+stream) → `HybridNoteSearch.run` with `semanticMinScore 0.76` / `semanticRelativeGap 0.12` / `semanticPeakMargin 0.07` (new NotoSearch request fields, defaults leave Noto unchanged; measured on granite: unrelated text ≈0.70–0.73 vs related ≈0.80–0.86, and gibberish peaks only ≈0.04–0.05 above the corpus median vs ≥0.11 for real queries — without the gates every note surfaced and "no results" was unreachable) → one row per note (prefer snippet-bearing row) → `SummaryPromptBuilder` (top 8 distinct notes, 1 800 chars each, frontmatter stripped) → `OpenRouterClient.stream` with `NotoChat.defaultModel`. UI per brief: `.searchable` "Search notes", `ContentUnavailableView` empty/no-results, "N results for “q”" footnote header, rows title·date / snippet with stemmed whole-word emphasis (`SnippetEmphasis`) / path-derived breadcrumb, summary as paragraph (rendered via `SummaryPromptBuilder.rendered`: inline Markdown → styling, `* `/`- ` → `•`, prompt asks for plain prose) + "Summary" caption + "From the top N note(s) · AI-generated", needs-key link, "Summary unavailable · Retry", ellipsis menu (OpenRouter key…, Rebuild index), re-run on `.notoSearchIndexDidChange`.
- **Browse** (`Noto2/Browse/`): `BrowseDestination` enum shared with Search; `FolderListView` over `MarkdownNoteStore` with `ExplorerSorting`; `NoteScreen` = `EditorContentView` + `NoteEditorSession` (load on task, `persistFinalSnapshotIfNeeded` on disappear), find toggle, tab bar hidden.
- **Settings** (`Noto2/Settings/OpenRouterSettingsSheet.swift`): key (Keychain via `OpenRouterKeyStore`), base-URL override, vault path + "Choose a different vault…" (`resetVault`).
- **Tooling:** `.maestro/seed-vault.sh` gained `--bundle-id` so Noto 2's container can be seeded.

## Residual Risks

- Device signing/TestFlight for `com.eugenechan.Noto2` not set up (Automatic signing; entitlements file is an empty dict — iCloud-picked folders work via security-scoped bookmarks without iCloud entitlements, verified only on the simulator's local vault). Use the `testflight-deploy` skill when shipping.
- Semantic-leg gate constants (0.76 / 0.12) are calibrated from eight probe sentences, not an eval set; the plan's search eval set (`.claude/brainstorm/gbrain-noto-capabilities.md` §2) is still the real yardstick. In the simulator the semantic index had not finished embedding the fresh capture, so semantic-only recall of a just-filed note was not observed live.
- Keyboard behaviour was exercised with the simulator's hardware keyboard attached (accessory bar only); the status line's position above a software keyboard and the editor's first-responder state after Send are unverified on device.
- Stage 2 (promoting `NotoShared/Storage` and `NotoShared/Editor` into packages) is deliberately deferred; until then the two apps share source files, not modules.
- The swipe-up commit is not captured on video: both simulator recorders on this machine (flowdeck's and Apple's) write 0.067 s two-frame files and silently swallow idb HID input while running — every recorded interaction run failed, every recorder-free run succeeded. Static states are screenshot-proven; the animation itself is unverified on film.
- The docked toolbar branch was restructured (shared rail/pinned code, host indirection); it reproduces the previous constraints exactly but Noto's toolbar visuals were re-verified only by build, not screenshot.
- Auditor minors left as-is: semantic-only rows carry no date (`HybridSearchFusion` synthesizes `updatedAt: nil`); a heading-less capture is titled by filename in Search (index title) but by first line in Browse (`MarkdownNote.title`); with a hardware keyboard the editor accessory bar floats over the tab bar.
- Pre-existing NotoTests failures (10) remain in the tree from the in-progress tags/deep-link/editor work and are unrelated to this change.

## Bugs

Audit round 1 (PARTIAL, `.codex/evidence/20260824-001733-ios-visual-audit/`): (1) gibberish queries returned semantic hits so the no-results state was unreachable → fixed with `semanticPeakMargin`; (2) summary showed raw Markdown → fixed (prose prompt + `AttributedString(markdown:)` rendering); (3) no entitlements file → added `Noto2/Noto2.entitlements` + `CODE_SIGN_ENTITLEMENTS`. Round 2 audit (`.codex/evidence/20260824-003537-ios-visual-audit/evidence.md`): **PASS** — all three fixes verified on the installed build (gibberish → system No Results with no summary spent; clean-prose summaries; entitlements dict in the signed product), plus Capture/Search/Browse re-confirmed with on-disk proof and an 80 s recording.
