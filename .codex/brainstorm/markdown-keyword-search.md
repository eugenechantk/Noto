# Markdown Keyword Search Brainstorm

Date: 2026-04-22

## Goal

Design Noto search for the markdown-file era, starting with keyword search.

The first version should make the current search button useful without rebuilding the full v1 hybrid search stack. It should search the user's real markdown vault, work offline, stay fast enough for interactive use, and be rebuildable from files if the derived index is deleted.

## Prior Inputs Reviewed

- `.claude/Search/Brainstorm-search.md`
- `.claude/Search/PRD-search-foundation.md`
- `.claude/Search/PRD-keyword-search.md`
- `.claude/Search/Spec-keyword-search.md`
- `.claude/Search/Plan-search-completion.md`
- `.claude/Noto v2/Brainstorm-new-direction.md`
- `.claude/AI Chat/Brainstorm-ai-chat-claude.md`
- `.claude/brainstorm/mac-ui-ipad-os-redesign.md`
- `.codex/brainstorm/shared-note-list-architecture.md`
- `.codex/brainstorm/web-clipping-universal-capture.md`
- Current `NotoVault`, `MarkdownNoteStore`, `VaultDirectoryLoader`, `NoteTitleResolver`, and `VaultFileWatcher` code

## What Changed Since the Old Search Plan

The old search plan was correct for v1, but its primitives are no longer correct.

Old model:

- SwiftData `Block` is the source of truth.
- Dirty tracking uses block UUIDs.
- Search result identity is `blockId`.
- Breadcrumb is a block ancestor chain.
- Index reconciliation compares SwiftData timestamps.

Current model:

- Markdown files are the source of truth.
- Folders are real directories.
- Note identity is frontmatter `id`, falling back to a stable URL-derived ID when needed.
- Title comes from markdown body via `NoteTitleResolver`.
- The current app has no compiled paragraph identity/index package yet.
- External file edits and iCloud changes are real first-class inputs.

The core shift: search should index a vault scan, not an app database.

## Recommendation

Start with note-level and section-level keyword search in a new package, `NotoSearch`, backed by a sidecar SQLite FTS5 index under the vault's `.noto/` directory.

Do not require stable paragraph IDs for v1 keyword search. They are valuable for mentions, sentence-level AI grounding, and future semantic search, but they are not necessary to ship useful full-text search.

The minimum useful search unit should be:

1. `note`: one result for a whole markdown file.
2. `section`: one result for a heading-bounded region inside a note.

Sections are a better first primitive than paragraphs because markdown users naturally scan by headings, sections survive small line edits better than paragraph IDs, and they avoid the complexity of cross-note paragraph identity before mentions exist.

## Product Shape

Search should answer two different user intents:

- "Find the note where I wrote this."
- "Find the specific passage inside a note."

The result list can mix both.

Note result:

- Title: note title
- Subtitle: relative folder path
- Snippet: best FTS5 snippet from the whole note
- Action: open note

Section result:

- Title: section heading, or note title if the section has no heading
- Subtitle: `Folder / Note Title`
- Snippet: best matching text within that section
- Action: open note and scroll to approximate line/heading

For the first implementation, opening the note is enough. Scroll-to-section can follow after the editor has a stable API for line or range navigation.

## Query Behavior

The first keyword search should support:

- Case-insensitive term matching.
- Stemming through FTS5 `porter unicode61`.
- Prefix matching for the final token while typing, for example `sear` becomes `sear*`.
- Quoted phrase search when quotes are balanced.
- Exact title boost outside FTS5 scoring.
- Folder/path text as a lightly weighted searchable field.

It should not require advanced syntax in the UI. Boolean operators can be supported internally by FTS5 only if sanitization makes them safe and predictable.

## Index Location

Use a sidecar directory inside the vault:

```text
<vault>/
  .noto/
    search.sqlite
```

Rationale:

- The index travels with the vault.
- It is clearly derived data.
- It can be deleted and rebuilt.
- It avoids Application Support drift when the same vault is opened from multiple app installs or platforms.

Hidden `.noto` files are already compatible with directory loading because `VaultDirectoryLoader` skips hidden files.

## Proposed FTS5 Schema

Keep normal metadata in ordinary tables and searchable text in FTS5 tables.

```sql
CREATE TABLE notes (
    note_id TEXT PRIMARY KEY,
    relative_path TEXT NOT NULL UNIQUE,
    title TEXT NOT NULL,
    folder_path TEXT NOT NULL,
    created_at TEXT,
    updated_at TEXT,
    file_modified_at TEXT NOT NULL,
    content_hash TEXT NOT NULL
);

CREATE TABLE sections (
    section_id TEXT PRIMARY KEY,
    note_id TEXT NOT NULL REFERENCES notes(note_id) ON DELETE CASCADE,
    heading TEXT NOT NULL,
    level INTEGER,
    line_start INTEGER NOT NULL,
    line_end INTEGER NOT NULL,
    section_index INTEGER NOT NULL,
    content_hash TEXT NOT NULL
);

CREATE VIRTUAL TABLE note_fts USING fts5(
    title,
    folder_path,
    content,
    note_id UNINDEXED,
    tokenize='porter unicode61'
);

CREATE VIRTUAL TABLE section_fts USING fts5(
    heading,
    content,
    note_id UNINDEXED,
    section_id UNINDEXED,
    line_start UNINDEXED,
    tokenize='porter unicode61'
);

CREATE TABLE index_metadata (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);
```

Possible future tables:

- `paragraphs` for stable paragraph IDs.
- `paragraph_fts` when paragraph-level search becomes useful.
- `note_embeddings` and `section_embeddings` for semantic search.

## Search Units

### Note Unit

Index the whole markdown body, with frontmatter stripped.

Use this for broad recall. It helps queries where the user's terms are scattered across a note rather than concentrated in one section.

### Section Unit

Split markdown by ATX headings:

- `#`
- `##`
- `###`
- deeper headings can be included, but start by treating all headings as boundaries

Each section includes:

- heading text
- body text until the next heading of any level
- line start and line end
- note ID and relative path

If a note has body text before the first heading, create section index `0` with heading equal to the note title.

### Why Not Paragraphs First

Paragraph search sounds precise, but it pulls in hard problems that do not need to block keyword search:

- preserving paragraph identity across arbitrary external edits
- scroll-to-paragraph in TextKit
- cross-note move identity
- paragraph split and merge behavior
- mention compatibility

Sections avoid most of that while still being much more useful than note-only search.

## Markdown Text Extraction

Create a pure parser/extractor in `NotoVault` or `NotoSearch`:

```swift
struct SearchDocument {
    let noteID: UUID
    let relativePath: String
    let title: String
    let folderPath: String
    let createdAt: Date?
    let updatedAt: Date?
    let contentHash: String
    let plainText: String
    let sections: [SearchSection]
}

struct SearchSection {
    let stableID: UUID
    let heading: String
    let level: Int?
    let lineStart: Int
    let lineEnd: Int
    let plainText: String
    let contentHash: String
}
```

Extraction rules:

- Strip YAML frontmatter.
- Preserve visible text from headings, paragraphs, list items, todos, blockquotes, and table cells.
- Remove markdown syntax markers where they hurt matching: heading `#`, list bullets, todo boxes, emphasis markers, inline code backticks.
- Keep link text and optionally URL text.
- Include source note generated blocks from imports, because source notes should be searchable.
- Ignore hidden `.noto` files and non-markdown files.

The extractor does not need a full CommonMark parser for the first pass. A line-oriented parser is enough for headings, sections, plain text, and snippets.

## Stable IDs

Use frontmatter IDs for notes whenever available.

For sections, use deterministic IDs derived from:

```text
note_id + section heading path + section_index
```

This is stable enough for search result identity, but not promised as a permanent mention anchor. If headings are renamed or sections reorder, section IDs can change. That is acceptable for v1 keyword results.

If a note lacks frontmatter, use `VaultDirectoryLoader.stableID(for:)` and consider writing frontmatter later as a separate migration.

## Indexing Strategy

The simplest reliable approach is scan-and-diff by file metadata plus content hash.

### Initial Build

1. Walk the vault recursively, skipping hidden directories and files.
2. Read each `.md` file using coordinated reads where needed.
3. Parse frontmatter and body.
4. Extract note and section documents.
5. Upsert into metadata tables and FTS5 tables.
6. Delete index rows whose relative paths no longer exist.

### Incremental Updates

Trigger from:

- app launch
- search screen open
- app background, best effort
- `VaultFileWatcher` change notifications
- in-process saves from `MarkdownNoteStore.saveContent`
- note rename, move, delete, create

For each changed file:

1. Read actual file content.
2. Compute hash.
3. If hash and relative path are unchanged, skip.
4. Re-extract note and sections.
5. Replace that note's note row, section rows, and FTS rows in one transaction.

For directory-level changes, do a cheap vault rescan and only reindex changed hashes.

This is simpler than v1 dirty block tracking because the filesystem is the database and file hashes are the reconciliation source.

## Ranking

Use FTS5 BM25 as the base score, then apply deterministic boosts.

Start weights:

- exact note title match: strong boost
- title contains all query terms: strong boost
- heading contains query terms: strong boost
- filename/folder path contains query terms: medium boost
- section result with compact matching text: medium boost
- note result matching only low-signal imported content: no boost
- very long note result: slight penalty unless title also matches

Result merging:

1. Query `note_fts`.
2. Query `section_fts`.
3. Convert both to a common `SearchResult`.
4. Normalize scores within each result type.
5. Apply boosts.
6. Interleave by final score.
7. Deduplicate obvious duplicates:
   - If a section and its parent note both match, keep both only when the note-level match has a distinct reason, such as title/path match.
   - Otherwise prefer the section because it is more actionable.

## Search Result Type

```swift
enum SearchResultKind: Sendable {
    case note
    case section
}

struct SearchResult: Identifiable, Sendable {
    let id: UUID
    let kind: SearchResultKind
    let noteID: UUID
    let fileURL: URL
    let title: String
    let breadcrumb: String
    let snippet: String
    let lineStart: Int?
    let score: Double
    let updatedAt: Date?
}
```

This keeps the UI independent of FTS5 internals and future-proofs semantic search.

## UI Direction

Ship one global search surface first.

On iPhone:

- Tapping the bottom Search button opens a search sheet.
- Search field is focused immediately.
- Results update as the user types for keyword search.
- Empty state can show recent notes or nothing; avoid instructional copy in the main UI.

On iPad/macOS:

- Existing sidebar search can remain a title/folder filter.
- Global content search can use the same search sheet or command-palette-style overlay.
- Later, sidebar field can show "filter" behavior until Return opens global search.

This avoids overloading the sidebar search field before full search behavior is designed.

## Package Boundaries

Recommended first package:

```text
Packages/
  NotoSearch/
    Sources/NotoSearch/
      SearchIndexStore.swift      # SQLite + FTS5 wrapper
      MarkdownSearchIndexer.swift # vault scan and changed-file indexing
      MarkdownSearchEngine.swift  # query sanitization and ranking
      SearchTypes.swift
```

Potential shared extraction code can live in `NotoVault` if list/sidebar/search all need it:

```text
Packages/NotoVault/
  MarkdownSearchDocumentExtractor.swift
```

Keep app target code limited to:

- creating/opening the index for the selected vault
- calling index refresh triggers
- presenting search UI
- opening selected result

## Implementation Phases

### Phase 1: Queryless Index Prototype

Build and test:

- vault recursive markdown scan
- frontmatter parsing with current `id`, `created`, `updated`/`modified` compatibility
- note/section extraction
- `.noto/search.sqlite` creation
- full rebuild
- changed-file reindex by hash

Acceptance:

- A temp vault fixture indexes expected notes and sections.
- Deleting `.noto/search.sqlite` and rebuilding produces the same rows.

### Phase 2: Keyword Engine

Build and test:

- FTS5 note and section tables
- query sanitizer
- exact/stem/prefix/phrase matching
- snippets
- title/heading/path boosts
- mixed note and section result ranking

Acceptance:

- Search for a word in a markdown body returns the right note and section.
- Search for a heading strongly ranks that section.
- Search for a folder/name term can find a note even if body does not contain the term.

### Phase 3: App Integration

Build:

- search service owned per vault
- refresh on search open
- refresh on file watcher events
- mark/reindex changed note on in-process save
- search sheet for iOS bottom toolbar
- open note from result

Acceptance:

- Create note, type searchable text, open search, find it.
- Edit note, old term disappears and new term appears after refresh.
- Rename or move note, result path updates.
- Delete note, result disappears.

### Phase 4: Section Navigation

Build:

- pass line/range target into editor opening path
- scroll selected result into view
- highlight matching range briefly

Acceptance:

- Tapping a section result opens the note near the matching section.

### Phase 5: Prepare for Semantic Search

Only after keyword search is solid:

- add `SearchCorpusItem` abstraction shared by keyword and embeddings
- decide whether semantic index should use notes + sections or add paragraph chunks
- add embeddings as a separate package/pipeline
- reuse ranking result type

## Test Fixtures

Create package fixtures for:

- frontmatter with `updated`
- frontmatter with legacy `modified`
- no frontmatter
- daily note
- nested folders
- imported source note with hidden generated blocks
- long note with multiple headings
- todos and bullets
- links and inline code
- external edit simulation
- delete and rename simulation

## Open Questions

1. Should `.noto/search.sqlite` be hidden from iCloud sync or allowed to sync with the vault?
   Recommendation: allow it initially if it lives in the vault, but treat it as disposable and always validate against file hashes.

2. Should generated source-note content be indexed by default?
   Recommendation: yes. Search is the main reason to capture full content. Later add filters for source notes if noise becomes real.

3. Should sidebar search become global content search?
   Recommendation: not first. Keep sidebar filtering predictable, and use the Search button/sheet for global search.

4. Should section IDs be considered stable?
   Recommendation: no. They are stable enough for result rows, not for permanent links.

5. Should search write missing frontmatter IDs into old markdown files?
   Recommendation: not in the search pass. Index with path-derived IDs and make frontmatter normalization a separate explicit migration.

6. Should keyword indexing run on every keystroke?
   Recommendation: no. Save writes already happen frequently enough. Reindex on save/debounce/file change/search open.

## Risks

- FTS5 query syntax can leak into the user experience if sanitization is weak.
- Imported full-content source notes may dominate results unless title/heading boosts are tuned.
- Reindexing entire long notes on every autosave could be wasteful, so changed-file debounce matters.
- Multiple processes editing the same vault can race on `.noto/search.sqlite`; keep transactions short and rebuildable.
- iCloud files may appear before they are readable; indexer should treat unreadable files as skipped, not deleted.

## First PR Recommendation

Implement `NotoSearch` with only package-level tests and no UI.

Scope:

- `.noto/search.sqlite`
- full vault scan
- note/section extraction
- FTS5 index
- keyword query API
- ranking and snippets

Leave app integration for the second PR. That keeps the hard data-layer decisions reviewable and avoids mixing search UI with indexing correctness.
