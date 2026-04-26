# Feature: Full-Text Keyword Search

## Status

Implementing phase by phase. Phase 0, Phase 1, and Phase 2 are complete and verified in `Packages/NotoSearch` with package-level tests, including live-vault read-only integration coverage against `/Users/eugenechan/Library/Mobile Documents/com~apple~CloudDocs/Noto`. The package-level scoped query API for `Title` vs `Title + Content` is also implemented ahead of app UI integration.

## Prior Search Planning Reviewed

- `.codex/brainstorm/markdown-keyword-search.md`
- `.codex/feature/sidebar-deep-title-search.md`
- `.claude/Search/Brainstorm-search.md`
- `.claude/Search/PRD-search-foundation.md`
- `.claude/Search/PRD-keyword-search.md`
- `.claude/Search/PRD-hybrid-search-and-ui.md`
- `.claude/Search/Spec-search-foundation.md`
- `.claude/Search/Spec-keyword-search.md`
- `.claude/Search/Spec-hybrid-search-and-ui.md`

## Key Decision From Review

Use the newer markdown-era search plan as the baseline.

The older `.claude/Search` docs were designed for the SwiftData block model: block IDs, dirty block tracking, block breadcrumbs, SwiftData date joins, and later semantic/HNSW search. That architecture no longer matches Noto's current source of truth.

Current Noto uses markdown files and real folders as the source of truth. Search should therefore index vault files, not SwiftData blocks. The right first step is a rebuildable sidecar SQLite FTS5 index under `<vault>/.noto/search.sqlite`, with note-level and section-level result units.

## Package Namespace Reset

The old SwiftData/block-era package has been renamed out of the way:

```text
archive/Packages/NotoSearchLegacy/
```

Its package, product, target, test target, and archived imports now use `NotoSearchLegacy`.

A new active package now owns the `NotoSearch` name:

```text
Packages/NotoSearch/
  Package.swift
  Sources/NotoSearch/
    SearchTypes.swift
  Tests/NotoSearchTests/
    SearchTypesTests.swift
```

This new package is intentionally small. It establishes the markdown-era public result/document/section types without carrying forward SwiftData block search, dirty block tracking, semantic search, HNSW, or hybrid ranking assumptions.

## User Story

As a Noto user, I want keyword search to find words inside note bodies, not only note titles, so that captured source content and my own long notes are searchable from the app.

## User Flow

1. User opens the search action from the bottom toolbar or sidebar toolbar.
2. User types a keyword or phrase.
3. User chooses a search scope: `Title` or `Title + Content`.
4. In `Title`, Noto searches note titles only.
5. In `Title + Content`, Noto searches note titles, headings, folder context, and note body text.
6. Results update with matching notes and sections, including a short snippet and breadcrumb.
7. User taps a result.
8. Noto opens the matching note.
9. In a later phase, section results can open near the matched heading or text range.

## Success Criteria

- [x] Searching for a word that appears only in a markdown note body returns that note.
- [x] Searching imported Reader/Readwise capture body content returns the matching capture note.
- [x] Searching for a heading ranks the matching section highly.
- [x] Searching for a title still ranks exact title matches above body-only matches.
- [x] Searching nested notes shows enough path context to identify where the result lives.
- [x] Creating or editing a note makes new body text searchable after app-launch refresh, save-time indexing, or search-open refresh.
- [x] Renaming, moving, or deleting a note updates search results without stale paths.
- [x] Deleting `.noto/search.sqlite` and rebuilding restores equivalent search results.
- [x] Query input is sanitized so normal punctuation, quotes, and special characters do not expose raw FTS5 syntax errors.
- [x] Search UI provides an explicit scope control for `Title` vs `Title + Content`.
- [x] `Title` scope returns only note-title matches and does not include body-only or section-only matches.
- [x] `Title + Content` scope includes note-title, heading, folder context, and body matches.
- [x] The first usable UI does not make sidebar filtering confusing: global full-text search is visually distinct from the current sidebar title filter.

## Platform & Stack

- **Platform:** iOS, iPadOS, macOS
- **Language:** Swift
- **Key frameworks:** SwiftUI, Swift Testing, Foundation, SQLite FTS5 through SQLite C API
- **Search package:** `Packages/NotoSearch`
- **Legacy search package:** `archive/Packages/NotoSearchLegacy`
- **Existing related package:** `Packages/NotoVault`

## Recommended Product Shape

Keep two search concepts separate at first:

- Sidebar filtering remains the lightweight title/folder tree filter.
- Global search becomes the full-text search surface opened by the Search button and command.

Recommended first UI:

- Search sheet.
- One focused search field.
- Segmented scope control: `Title + Content` first/default, `Title` second.
- Mixed result list:
  - note result: note title, folder path, and snippet when the note body provides matching context
  - section result: note title, vault-relative file path plus heading marker path such as `meeting_notes/01.md/### first subheading`, and snippet
- If a section result and its parent note result both match, show the section result and hide the parent note result from the visible list.
- Tapping a result opens the note.

Default scope recommendation: `Title + Content` for the global search surface, with the last chosen scope remembered per app session. `Title` should remain available for fast note lookup and for users who are using search as a launcher.

Platform presentation:

- iOS/iPadOS: reuse the existing note search sheet surface.
- macOS: replace the current search-button popover with a macOS sheet that closely mirrors the iOS/iPadOS search sheet design.
- The existing sidebar inline/title filter remains separate from global keyword search.

Do not make the existing sidebar tree field silently switch from title filtering to full-text search in the first pass. That would change its mental model and make folder expansion/result nesting harder to reason about.

## Recommended Architecture

Use the new active `NotoSearch` package for the index and query engine.

```text
Packages/
  NotoSearch/
    Sources/NotoSearch/
      SearchTypes.swift
      SearchIndexStore.swift
      MarkdownSearchDocumentExtractor.swift
      MarkdownSearchIndexer.swift
      MarkdownSearchEngine.swift
    Tests/NotoSearchTests/
```

Keep app target code thin:

- own one search service per active vault
- trigger refresh on app launch and search open
- connect file watcher and in-process save/move/delete events to indexing
- present search UI
- open selected results

## Search Units

Index both:

1. `note`: the full markdown body with frontmatter stripped.
2. `section`: heading-bounded chunks inside a note.

Sections are the right v1 granularity. They are more actionable than whole notes, but avoid the unstable paragraph identity and TextKit scroll-target complexity that would come with paragraph-level search.

## Index Location

```text
<vault>/
  .noto/
    search.sqlite
```

Rationale:

- derived and rebuildable
- scoped to the vault
- compatible with multiple app installs opening the same vault
- hidden from the normal note tree because current loaders skip hidden files

Decision: `search.sqlite` is disposable derived data. Markdown files remain the only source of truth. The index may live under `.noto/` and may be deleted, rebuilt, or replaced whenever schema metadata, file hashes, or path reconciliation show it is stale.

## FTS5 Schema Direction

Use normal tables for metadata and FTS5 virtual tables for searchable text.

Use `note_id` as the join key between ordinary metadata tables and FTS5 tables. The `note_id` comes from frontmatter `id` when present; otherwise the indexer derives a stable fallback ID from the note's normalized vault-relative path. The markdown file remains the source of truth, so `relative_path` is still stored and reconciled on every scan.

Core tables:

- `notes`: note ID, relative path, title, folder path, file modified date, content hash
- `sections`: section ID, note ID, heading, line start/end, section index, content hash
- `note_fts`: title, folder path, content, note ID
- `section_fts`: heading, content, note ID, section ID, line start
- `index_metadata`: schema version and rebuild metadata

Use FTS5 tokenizer `porter unicode61` for stemming and Unicode-aware tokenization.

## Query Behavior

Support in v1:

- explicit search scopes: `Title` and `Title + Content`
- case-insensitive matching
- stemming through FTS5
- prefix matching for single-word queries while typing
- unquoted multi-word queries are treated as exact phrases by default
- balanced quoted phrase search
- title, heading, path, and last-updated recency boosts outside raw FTS score
- snippets from FTS5

Avoid exposing advanced FTS syntax in the UI. Treat user text as plain text, then transform it into safe FTS syntax internally.

Scope semantics:

- `Title`: search note titles only; return note results only. Folder path is displayed for context but should not create a match by itself.
- `Title + Content`: search note titles, headings, folder context, and note body text; return mixed note and section results.
- Mention lookup should use the same indexed title-only query path, with a smaller result limit and no body/section matches.

## Indexing Strategy

Use scan-and-diff by path, file metadata, and content hash.

Initial build:

1. Walk the vault recursively.
2. Skip hidden directories and files.
3. Read `.md` files.
4. Strip frontmatter and extract title, note ID, sections, and plain text.
5. Upsert notes, sections, and FTS rows in transactions.
6. Delete index rows for paths that no longer exist.

Incremental refresh:

1. Trigger on search open, app launch, file watcher events, and app-originated create/save/rename/move/delete.
2. For changed files, read actual content and compute hash.
3. If hash and path are unchanged, skip.
4. Replace that note's metadata, sections, and FTS rows in one transaction.
5. For directory-level changes, do a cheap rescan and reindex changed hashes only.

Treat unreadable iCloud files as skipped, not deleted.

## Implementation Phases

### Phase 0: Namespace Reset

Status: Verified.

- archived SwiftData-era `NotoSearch` renamed to `NotoSearchLegacy`
- new active `Packages/NotoSearch` package created
- initial markdown-era search document, section, and result types added
- scaffold package tests added

Scope:

- Establish a clean markdown-era `NotoSearch` package name.
- Keep the old SwiftData/block-era package available as `NotoSearchLegacy`.

Non-goals:

- No FTS5 schema.
- No markdown vault scan.
- No search UI.

Verification gate:

- `cd Packages/NotoSearch && swift test` passed with scaffold tests.
- `cd archive/Packages/NotoSearchLegacy && swift test` passed after the rename.

### Phase 1: Package Prototype

Build out the new `NotoSearch` package with no app UI integration.

Status: Verified.

Scope:

- Add markdown vault scanning.
- Add frontmatter stripping, title resolution, note ID extraction, fallback ID generation, plain-text extraction, and heading-bounded section extraction.
- Add a SQLite sidecar store at an injected index directory, defaulting later to `<vault>/.noto`.
- Add full rebuild and changed-file refresh.
- Add read-only live-vault indexing tests that write the index to a temp directory, not the live vault.

Non-goals:

- No app target integration.
- No SwiftUI search UI.
- No editor scroll-to-section.
- No semantic search or embeddings.

Expected files/modules touched:

- `Packages/NotoSearch/Sources/NotoSearch/SearchTypes.swift`
- `Packages/NotoSearch/Sources/NotoSearch/MarkdownSearchDocumentExtractor.swift`
- `Packages/NotoSearch/Sources/NotoSearch/SearchIndexStore.swift`
- `Packages/NotoSearch/Sources/NotoSearch/MarkdownSearchIndexer.swift`
- `Packages/NotoSearch/Tests/NotoSearchTests/*`

Deliver:

- vault scanner
- markdown text extractor
- note and section models
- `.noto/search.sqlite` creation
- full rebuild
- changed-file reindex
- package-level Swift tests

Verification gate:

- `cd Packages/NotoSearch && swift test` passed.
- Package tests prove fixture vault scan/extraction/index metadata behavior.
- Live-vault integration test indexes at least hundreds of markdown documents from the current vault into a temp index.
- Changed-file refresh tests prove edit, delete, move/rename, and stale-path reconciliation.
- Rebuild after deleting the temp index produces equivalent indexed counts.

Reason: this isolates the hard correctness questions before UI state, navigation, and platform differences enter the work.

### Phase 2: Keyword Query Engine

Deliver:

Status: Verified.

Scope:

- Add FTS5 note and section tables.
- Add query sanitization for normal text, punctuation, quotes, phrases, and final-token prefix matching.
- Add mixed note/section search API returning `SearchResult`.
- Add title, heading, path, and last-updated recency boosts over FTS5 BM25.
- Add read-only live-vault search tests against the temp index built from the current vault.

Non-goals:

- No UI presentation.
- No result tapping/opening.
- No scroll-to-match.
- No semantic or hybrid search.

Expected files/modules touched:

- `Packages/NotoSearch/Sources/NotoSearch/SearchIndexStore.swift`
- `Packages/NotoSearch/Sources/NotoSearch/MarkdownSearchEngine.swift`
- `Packages/NotoSearch/Tests/NotoSearchTests/*`

- FTS5 note and section tables
- safe query sanitizer
- exact, stemmed, prefix, and phrase matching
- snippets
- title, heading, path, and last-updated recency boosts
- mixed note/section result ranking
- package-level Swift tests

Verification gate:

- `cd Packages/NotoSearch && swift test` passed with 20 tests.
- Package tests prove body-only search, capture-body search, heading ranking, title boosting, last-updated recency ranking, prefix search, phrase search, and punctuation-safe queries.
- Package tests prove `Title` scope excludes body-only, heading-only, and path-only matches while `Title + Content` preserves body and section matches.
- Package tests prove visible search results hide a note match when a section from that same note also matches, while keeping standalone note matches.
- Live-vault integration test performs real searches against the temp index built from the current vault.
- Previous Phase 1 tests still pass before moving to Phase 3.

### Phase 3: App Integration

Deliver:

- package query scope API: done in `Packages/NotoSearch`
- search service owned per vault
- refresh on app launch and search open
- search sheet queries the existing persisted index immediately while refresh runs in the background
- shared refresh coordinator deduplicates concurrent app-launch, foreground, file-watcher, and search-open refresh requests per vault
- refresh from `VaultFileWatcher`
- explicit indexing hooks for in-process save, create, rename, move, and delete
- global search UI for iOS/iPadOS/macOS with `Title` and `Title + Content` scope control
- iOS/iPadOS uses the existing search sheet surface
- macOS search button presents the same sheet-style search surface instead of a popover
- open note from result

Verification gate:

- package tests prove `Title` scope excludes body-only and section-only matches.
- package tests prove `Title + Content` still includes body-only, heading, and capture-content matches.
- iOS simulator validation proves `Title + Content` is first/default and returns body matches; switching to `Title` suppresses body-only matches.
- macOS build/launch validates the search button no longer depends on the removed popover path and the shared sheet compiles/runs on macOS.

Verification recorded:

- `cd Packages/NotoSearch && swift test` passed with 20 tests.
- `flowdeck build` passed for iOS simulator.
- `flowdeck build -s Noto-macOS -D "My Mac"` passed.
- `flowdeck run -s Noto-macOS -D "My Mac"` launched successfully.
- iOS simulator evidence: `.flowdeck/automation/sessions/2F96A41A/latest.jpg`.
- Section-over-note display rule evidence: `.flowdeck/automation/sessions/7AD33694/latest.jpg`.

### Phase 4: Section Navigation

Deliver:

- pass line/range target through note opening
- editor scroll-to-section support
- optional transient match highlight

Phase 4 should follow the basic search UI because TextKit scroll targeting is separate risk.

### Phase 5: Semantic Search Preparation

Do not start semantic search until keyword search is solid.

Later work:

- shared `SearchCorpusItem`
- embeddings over notes/sections or paragraph chunks
- hybrid ranking
- optional natural-language/date filters

## Test Strategy

### Package Tests

Create `Packages/NotoSearch/Tests/NotoSearchTests`.

Core cases:

- indexes a temp vault with nested folders
- ignores hidden `.noto` content
- strips frontmatter from indexed body
- uses `note_id` as the metadata-to-FTS join key
- uses frontmatter `id` when present and path-derived fallback ID when absent
- extracts sections from ATX headings
- indexes source-note generated content
- finds body-only words
- finds imported capture body text
- ranks exact title matches above body-only matches
- ranks heading matches highly
- supports prefix search for final token
- supports balanced quoted phrase search
- handles punctuation and unbalanced quotes safely
- reindex after edit removes old terms and adds new terms
- rename/move updates path and stale rows
- delete removes results
- rebuild after deleting `search.sqlite` restores results

### App Tests

After package behavior is stable:

- app-target tests for search service ownership and result-to-note opening
- SwiftUI/view-model tests for query state and result selection where possible
- simulator validation for the global search UI on iPhone and iPad because this changes navigation and interaction

## Integration Notes From Current Code

- `NotoSplitView` already owns `sidebarSearchText` and search presentation state.
- `NotoSidebarView` currently filters `SidebarTreeNode` rows by `row.name` only.
- `.codex/feature/sidebar-deep-title-search.md` already established full-tree title filtering without mutating expansion state.
- `VaultDirectoryLoader` already skips hidden files and derives note titles from markdown prefixes.
- `VaultDirectoryLoader.stableID(for:)` can be reused as the fallback ID strategy unless `NotoSearch` needs its own public helper.
- `MarkdownNoteStore`, `VaultFileWatcher`, and app-originated note operations are the likely integration points for freshness.

## Open Questions

1. Should the first full-text UI replace the search popover, or should it open a larger sheet/overlay from the same button?
   Recommendation: larger sheet/overlay. Results need snippets and breadcrumbs.

2. Should sidebar search ever include body matches?
   Recommendation: not in the first pass. Keep sidebar search as filtering and global search as retrieval.

3. Should generated Reader/Readwise content be indexed by default?
   Recommendation: yes. Captured full content is only useful if searchable.

4. Should v1 include scroll-to-match?
   Recommendation: no. Open the note first; add section navigation after the index and UI are reliable.

5. Should old `.claude/Search` semantic search plans be preserved?
   Recommendation: preserve as future context, but do not implement them directly. Rebase semantic search on markdown notes/sections after keyword search ships.

## Risks

- SQLite C API wrapping can become noisy; keep the package API narrow and heavily tested.
- FTS5 query syntax can leak through if sanitization is weak.
- Large Reader/Readwise captures may dominate body matches; ranking boosts need to favor titles/headings/path when appropriate.
- Autosave plus large files can cause excess reindexing; debounce and hash checks matter.
- iCloud placeholders can be unreadable; skipped-vs-deleted behavior must be explicit.
- Multi-window or multi-process access to the same vault can race on the sidecar DB; transactions should be short and rebuild should be safe.

## Review Recommendation

Approve Phase 1 and Phase 2 as the first implementation slice:

- create `NotoSearch`
- build the markdown scanner/extractor
- create the FTS5 sidecar index
- implement keyword search API
- prove it with package tests only

Do UI integration as a second slice after the data layer is reviewable.
