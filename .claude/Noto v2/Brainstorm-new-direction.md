# Brainstorm: Noto v2 — Note-Based with Paragraph Mobility

A clean break from the outline-based model. Noto becomes a note-taking app organized by folders and notes, where the atomic unit of interaction is the **paragraph** (not the block/bullet). Five pillars: daily notes, line-level mentions, hybrid search, **markdown files as the canonical storage format**, and **AI-operability** (every operation accessible via CLI, MCP, or API). Paragraph moving is just deleting from one note and inserting into another — standard editing, no special mechanism needed.

---

## The Shift

**v1 (outline):** Everything is a Block. Blocks nest infinitely. The whole app is one big tree. Navigation = drilling into deeper nodes. Mental model = a single interconnected outline.

**v2 (notes):** Notes are documents saved as markdowns. Folders organize notes. Within a note, paragraphs are the atomic moveable unit. Cross-note connections happen through mentions and search. Mental model = a filing cabinet where any paragraph can reference or move to any other note.

**Why the change:** The outline model creates cognitive overhead. Users think in notes and documents, not tree hierarchies. "Where did I put that?" is easier to answer when things live in named notes inside folders, not at depth 7 of an infinite outline. The outline's power (infinite nesting, flexible structure) becomes its weakness when everything is connected to everything and nothing has a clear home.

---

## The Five Pillars

### 1. Today's Note

Every day, the app surfaces a fresh note page for the current date. This is the default landing spot — open the app, start writing.

**Inspired by v1's Today's Notes concept**, but now it's a note with paragraphs inside it, not a hierarchy of blocks.

**What changes:**

- No Year > Month > Week > Day block hierarchy — just a note titled "2026-03-16" inside a single "Daily Notes" folder
- The note is a regular note with paragraphs. No special block protection or restricted editing.
- Auto-creation is dead simple: check if today's note exists in `Daily Notes/`, if not, create it. One file.
- All daily notes live flat in one folder, sorted by filename (date-based names sort chronologically naturally: `2026-03-15.md`, `2026-03-16.md`, etc.)
- The Today button bypasses browsing entirely — opens today's note directly

### 2. Per-Line Mentioning

Any line in a note can mention (reference) a specific line from another note. This creates a web of connections without the rigidity of an outline hierarchy.

**Inspired by v1's BlockLink concept** (source/target linking with bidirectional queries) and the @ trigger for the mention picker.

**What changes:**

- Links are between paragraphs across notes, not between blocks within the same tree
- The mention displays inline — e.g., "As I noted in [[Project Alpha > paragraph about API design]]"
- Backlinks panel: when viewing a note, see all paragraphs from other notes that mention paragraphs in this note

**Live cascade model:** Mentions always display the **current** text of the referenced paragraph. When the source paragraph is edited, every mention pointing to it updates automatically. There is no snapshot — the mention is a live window into the referenced content.

**Rendering:**

- Inline mention appears as a tappable chip/pill showing the **live current text** of the referenced paragraph (truncated if long)
- Tapping the mention navigates to the source note, scrolled to the referenced paragraph
- Edits to the referenced paragraph are reflected everywhere it's mentioned, immediately

**Why live cascade:**

- Always accurate — no stale references, no "updated" badges to manage
- Simpler mental model — a mention _is_ a reference to a living paragraph, not a frozen quote
- Mirrors how links work on the web (the linked page can change, but the link still points there)

**Trade-off:** Editing a paragraph could change how it reads in other notes where it's mentioned. This is acceptable because: (a) the mention is a reference, not a quote — the reader understands it points to another note, (b) the mention chip shows it's an embed, not inline prose, so context mismatch is expected, (c) the alternative (stale snapshots) is worse for a knowledge base.

**Three tiers of mention granularity:**

- **Note-level:** `@[[NoteName]]` → displays the note title, live. Tapping navigates to the note.
- **Paragraph-level:** `@[[NoteName#paragraphId]]` → displays the full paragraph text, live. Tapping navigates to that paragraph.
- **Sentence-level:** `@[[NoteName#paragraphId]]` + a sentence anchor stored in the sidecar index → displays just the matched sentence within the paragraph, live.

Sentence-level works by storing the original sentence text as an anchor in the index (not in the markdown file). On render, the app finds the best-matching sentence within the paragraph's current content (exact substring first, then fuzzy/edit-distance). If the sentence is edited, the mention updates to show the new wording. If the sentence is deleted or rewritten beyond recognition, the mention gracefully degrades to paragraph-level.

All three tiers follow the live cascade model — edits to the referenced content are always reflected in every mention, immediately, with no stale snapshots.

**Recommendation:** Support all three. The mention picker defaults to note-level (easiest), with drill-down to paragraph, then optional sentence selection within the paragraph.

**Open questions:**

- What about paragraph splits/merges? If a paragraph is split into two, the mention points to the original UUID — which half keeps it? (Likely the first half. Defer to later.)

**Deferred:** Mention picker UX (how the `@` trigger works, note/paragraph/sentence selection flow) — design later.

### 3. Hybrid Search

Keyword + semantic search at both the line and document level. This is the one area where v1's work is almost entirely reusable.

**Same concepts as v1's search brainstorm** (built from scratch, not reusing code):

- FTS5 for keyword search (BM25 ranking, porter stemming)
- CoreML bge-small-en-v1.5 for semantic embeddings (384-dim sentence transformer)
- HNSW via usearch for vector similarity (approximate nearest neighbor)
- Hybrid ranking algorithm (score normalization, alpha weighting, threshold filtering)
- Dirty-set tracking pattern (in-memory set → dirty table → lazy flush)
- Date filter extraction from natural language queries

**What changes:**

- **Dual-level indexing:** Both paragraphs and whole notes are indexed independently. Each paragraph gets its own embedding (as in v1). Additionally, the full note content is embedded as a single vector. FTS5 indexes both levels too — paragraph-level entries and a note-level entry (concatenated content). This gives two tiers of search candidates.
- **Flat ranking:** Document-level and paragraph-level results are treated as equals in the result list. A note match and a paragraph match compete on the same score scale — the ranker doesn't prefer one over the other. A note matching a broad query ("API design") and a specific paragraph matching a precise query ("GraphQL migration deadline") can both appear as top results.
- **Search results are a flat list** of mixed types: some results are whole notes, some are individual paragraphs. Each result shows what it is (note title vs. paragraph text + parent note breadcrumb).
- **Breadcrumb changes:** Instead of block ancestor chain, it's `Folder > Note Name` (for paragraph results) or just `Folder` (for note results).

**Indexing strategy:**

| Level | FTS5 | Embedding | HNSW |
|-------|------|-----------|------|
| Paragraph | Each paragraph indexed separately | 384-dim vector per paragraph | Stored in HNSW with paragraph UUID as key |
| Note | Full note content indexed as one entry | 384-dim vector for concatenated note text | Stored in same HNSW index with note UUID as key |

Both levels go through the same hybrid ranking pipeline (BM25 + cosine similarity → normalize → combine). The result list interleaves note-level and paragraph-level hits sorted by hybrid score.

**Note-level embedding:** The full note content (all paragraphs concatenated) is embedded as one vector. This captures the note's overall theme, which may not be obvious from any single paragraph. For very long notes, truncate to the model's max token length (512 tokens for bge-small-en-v1.5) — the beginning of the note usually captures the topic well enough.

**Dirty tracking:** When a paragraph changes, both the paragraph and its parent note are marked dirty. The note-level embedding and FTS5 entry are regenerated alongside the paragraph-level ones.

---

## Pillar 4: Markdown Files as Storage

Every note is a `.md` file on disk. Folders are real directories. The filesystem is the source of truth, not a database.

### Why Markdown Files

- **Portability:** Notes are readable and editable in any text editor, on any platform. No vendor lock-in. If the user stops using Noto, their notes are plain files.
- **Sync for free:** iCloud Drive, Dropbox, git — any file-sync service works. No custom sync protocol needed.
- **Transparency:** Users can browse their notes in Finder/Files. Nothing hidden in a SQLite database.
- **Interoperability:** Works with Obsidian, Bear, iA Writer, VS Code, any markdown tool. The user's notes are part of a broader ecosystem, not trapped in an app.
- **Longevity:** Markdown files will be readable in 50 years. A proprietary database might not be.

### File and Directory Layout

```
On My iPhone/
  Noto/                            # root vault folder (app's Documents directory)
    Projects/
      Project Alpha.md
      Project Beta.md
    Work/
      Meeting Notes/
        Standup 2026-03-16.md
    Daily Notes/
      2026-03-16.md
      2026-03-15.md
      2026-02-28.md
    .noto/                         # hidden sidecar directory (dot-prefix, hidden in Files app)
      index.sqlite                 # paragraph IDs, mentions, embeddings, FTS5, note metadata
      hnsw.index                   # vector search index
      config.json                  # vault settings
```

Everything lives together in one `Noto/` folder — markdown files and the sidecar index side by side. The `.noto/` directory holds all computed/derived data that can't live in the markdown itself. It's a **cache** — if deleted, it can be fully rebuilt by re-scanning the markdown files. Because it's co-located, moving or copying the entire `Noto/` folder preserves the index.

### Anatomy of a Note (Markdown File)

```markdown
---
id: 550e8400-e29b-41d4-a716-446655440000
created: 2026-03-16T09:30:00Z
modified: 2026-03-16T14:22:00Z
daily: true
daily_date: 2026-03-16
tags: []
---

# Mar 16, 2026

Had a great idea about the API refactor. We should move to GraphQL.

Need to check with @[[Project Alpha]] about their timeline.

This reminds me of what I wrote in @[[Project Alpha > the migration plan needs to account for backward compatibility]]
```

**Frontmatter (YAML):** Stores metadata that doesn't belong in the prose — note UUID, timestamps, daily note flag, tags. Standard YAML frontmatter, compatible with Obsidian/Jekyll/Hugo.

**Body:** Standard markdown. Paragraphs separated by blank lines (or single newlines — see paragraph granularity question). Mentions use a wikilink-inspired syntax.

### Note Identity — Frontmatter UUID

Every note has a stable UUID assigned at creation, stored in YAML frontmatter:

```yaml
---
id: 550e8400-e29b-41d4-a716-446655440000
---
```

This UUID is the note's permanent identity. **Filenames can change freely** (e.g., renaming `Untitled.md` to `My Project.md` when the user edits the title) without breaking anything — the sidecar index maps `frontmatter_id → current_file_path` and updates the path on rename. Paragraph identity, mentions, and search results all reference the frontmatter UUID, not the filename.

**Why not use the filename as identity:** Filenames change. The title is the filename (minus `.md`), and users edit titles. If identity was path-based, every title edit would break all paragraph UUIDs and mentions pointing to that note. Frontmatter UUIDs decouple identity from naming.

### Paragraph Identity — Sidecar Index

Paragraphs need stable IDs for mentions and moves, but markdown has no concept of paragraph identity. **Decision: sidecar index.** Paragraph IDs live in `.noto/index.sqlite`, not in the markdown files. Files stay completely clean.

The index maps `(frontmatter_note_id, contentHash, paragraphIndex)` → `paragraphId (UUID)`. The `frontmatter_note_id` is the note's UUID from frontmatter — stable across file renames. When a file changes, the index diffs against the previous version to maintain paragraph identity using content hash + position matching (see "How the Index Stays in Sync" for the full algorithm).

**Trade-off:** If the index is lost and rebuilt, paragraph-level mentions may not re-resolve if the paragraph content has changed significantly since the mention was created. Note-level mentions are unaffected (they resolve by frontmatter UUID, which is always present in the file). This is acceptable — the index is a local cache that rarely gets deleted, and the degradation is graceful (mention falls back to note-level).

### Mention Syntax in Markdown

Mentions need to be expressible in markdown so they survive file editing.

**Note-level mention:**

```markdown
Check @[[Project Alpha]] for details.
```

**Paragraph-level mention:**

```markdown
As noted in @[[Project Alpha#a1b2c3d4]]
```

The `@[[NoteName]]` syntax is inspired by Obsidian's wikilinks. The `#paragraphId` fragment targets a specific paragraph by its UUID in the sidecar index.

**Why ID-based targeting (not content snippets):**
Since mentions are live (cascade), the referenced paragraph's text can change at any time. A content-based snippet like `@[[Note > the migration plan needs backward compat]]` would break the moment that paragraph is edited. Storing the paragraph UUID ensures the mention always resolves to the right paragraph regardless of how its content changes.

**Trade-off — raw markdown readability:**
`@[[Project Alpha#a1b2c3d4]]` is less human-readable than a content snippet. This is acceptable because:

- The app renders it as a live-content chip — users never see the UUID in normal use
- If reading raw `.md` files outside the app, the note name is still visible (you know which note it points to, just not which paragraph)
- A comment could optionally be appended for readability: `@[[Project Alpha#a1b2c3d4]]<!-- API migration plan -->` — but this adds complexity and can go stale, so probably not worth it

**Resolution and rendering algorithm:**

1. Parse `@[[NoteName]]` or `@[[NoteName#paragraphId]]` from markdown
2. Look up the mention row in the index (by source paragraph + character range)
3. Resolve target note by name (case-insensitive, fuzzy match on file name)
4. If no paragraph ID → **note-level**: render chip with note title
5. If paragraph ID present → fetch paragraph's current content from index
6. If `sentence_anchor` is NULL → **paragraph-level**: render chip with full paragraph text
7. If `sentence_anchor` is set → **sentence-level**: fuzzy-match anchor against current paragraph content, render matched sentence. Falls back to full paragraph if no match.
8. If paragraph UUID not found (deleted or index rebuilt) → show as unresolved (note name still shown)

### File Watching and Index Sync

The app needs to detect when markdown files change (either from in-app editing or external edits in Finder/another app).

**In-app edits:** The app writes the markdown file directly, then updates the index in the same pass. Straightforward.

**External edits:** Use `DispatchSource.makeFileSystemObjectSource` or `NSFilePresenter` to watch the vault directory. When a file changes:

1. Re-read the file
2. Diff paragraphs against the index (content hash comparison)
3. Update/add/remove paragraph entries in the index
4. Re-index changed paragraphs in FTS5 and HNSW (via the existing dirty tracking pattern)
5. Re-resolve any mentions pointing to changed paragraphs

**Conflict handling (if the same file is edited in-app and externally simultaneously):**

- In-app takes priority while the note is open in the editor
- On editor close or app background, reconcile with the file on disk
- If both changed: show a diff/merge UI (or just last-write-wins for v1)

### What This Changes About Search

FTS5 and HNSW index paragraph and note text + IDs. The source of truth is the markdown files — the search pipeline reads from the sidecar index (which mirrors file content) and writes search indexes (FTS5 virtual tables, HNSW binary file) alongside it in `.noto/`.

### Daily Note File Creation

When the Today button is tapped or the app opens:

1. Compute today's file path: `Daily Notes/2026-03-16.md`
2. Check if the file exists
3. If not, ensure the `Daily Notes/` directory exists and write the file with frontmatter + title heading
4. Open it in the editor

Much simpler than the v1 block builder. Just file creation.

---

## Data Model (Sketch)

Two layers: **markdown files** (source of truth) and **SQLite index** (derived cache for fast queries).

### Source of Truth: The Filesystem

| Concept    | On disk                                      | Identity                           |
| ---------- | -------------------------------------------- | ---------------------------------- |
| Folder     | Directory                                    | Path (e.g., `Projects/`)           |
| Note       | `.md` file                                   | Frontmatter `id: UUID` + file path |
| Paragraph  | Text between blank lines in a `.md` file     | Sidecar index assigns stable UUID  |
| Daily note | `.md` file with `daily: true` in frontmatter | Frontmatter `daily_date`           |

No SwiftData. No `@Model` classes. The filesystem is the database.

### Sidecar Index: `.noto/index.sqlite`

A plain SQLite database (via C API, like the v1 FTS5 database) that caches derived data for fast in-app queries. Fully rebuildable from a vault scan.

**Tables:**

```sql
-- Note metadata (cached from frontmatter)
CREATE TABLE notes (
    id TEXT PRIMARY KEY,           -- UUID from frontmatter
    title TEXT NOT NULL,
    relative_path TEXT NOT NULL,   -- e.g. "Projects/Project Alpha.md"
    is_daily INTEGER DEFAULT 0,
    daily_date TEXT,               -- ISO date, nullable
    created_at TEXT NOT NULL,
    modified_at TEXT NOT NULL,
    content_hash TEXT NOT NULL     -- SHA256 of file content, for change detection
);

-- Paragraph index (derived from parsing each note)
CREATE TABLE paragraphs (
    id TEXT PRIMARY KEY,           -- assigned UUID
    note_id TEXT NOT NULL REFERENCES notes(id),
    content TEXT NOT NULL,
    content_hash TEXT NOT NULL,    -- for change detection and fuzzy matching
    line_start INTEGER NOT NULL,   -- line number in the file (for position stability)
    paragraph_index INTEGER NOT NULL, -- 0-based order within the note
    UNIQUE(note_id, paragraph_index)
);

-- Mentions (parsed from @[[...]] syntax in paragraph text)
-- Display text is always fetched live from the target — no snapshot stored.
-- Three granularity tiers:
--   Note-level:      target_note_id set, target_paragraph_id NULL, sentence_anchor NULL
--   Paragraph-level: target_note_id set, target_paragraph_id set,  sentence_anchor NULL
--   Sentence-level:  target_note_id set, target_paragraph_id set,  sentence_anchor set
CREATE TABLE mentions (
    id TEXT PRIMARY KEY,
    source_paragraph_id TEXT NOT NULL REFERENCES paragraphs(id),
    target_note_id TEXT,           -- resolved note UUID (nullable if unresolved)
    target_paragraph_id TEXT,      -- resolved paragraph UUID (nullable)
    target_note_name TEXT NOT NULL,-- parsed note name from @[[NoteName]] or @[[NoteName#id]]
    sentence_anchor TEXT,          -- original sentence text for fuzzy matching within paragraph
    range_start INTEGER,           -- char offset in source paragraph
    range_end INTEGER
);

-- Embeddings (for semantic search) — dual-level: paragraph + note
CREATE TABLE paragraph_embeddings (
    paragraph_id TEXT PRIMARY KEY REFERENCES paragraphs(id),
    embedding BLOB NOT NULL,       -- 384 floats as raw bytes
    model_version TEXT NOT NULL,
    content_hash TEXT NOT NULL,
    generated_at TEXT NOT NULL
);

CREATE TABLE note_embeddings (
    note_id TEXT PRIMARY KEY REFERENCES notes(id),
    embedding BLOB NOT NULL,       -- 384 floats (full note text, truncated to 512 tokens)
    model_version TEXT NOT NULL,
    content_hash TEXT NOT NULL,     -- hash of concatenated note content
    generated_at TEXT NOT NULL
);

-- FTS5 indexes (keyword search) — dual-level: paragraph + note
CREATE VIRTUAL TABLE paragraph_fts USING fts5(
    content,
    paragraph_id UNINDEXED,
    note_id UNINDEXED,
    tokenize='porter unicode61'
);

CREATE VIRTUAL TABLE note_fts USING fts5(
    content,                       -- full note text concatenated
    note_id UNINDEXED,
    tokenize='porter unicode61'
);

-- Dirty tracking — dual-level
CREATE TABLE dirty_paragraphs (
    paragraph_id TEXT PRIMARY KEY,
    operation TEXT NOT NULL DEFAULT 'upsert'  -- 'upsert' or 'delete'
);
```

### How the Index Stays in Sync

Every edit to a note — whether in-app or external — triggers a **re-parse and diff** of that note's paragraphs against what the index currently holds. The index never blindly overwrites; it diffs to preserve paragraph UUIDs.

**Trigger points:**
- **In-app edit:** Write the `.md` file → re-parse and diff → update index tables in the same pass. Atomic from the app's perspective.
- **External file change (file watcher):** Detect changed file → re-parse and diff → update/insert/delete paragraph rows → mark dirty for FTS5/HNSW re-indexing.
- **First launch or index corruption:** Full vault scan. Read every `.md` file, parse frontmatter + paragraphs, rebuild all index tables. For a vault with 1,000 notes averaging 20 paragraphs each (20K paragraphs), this takes ~2-5 seconds. Embeddings are regenerated lazily via the dirty tracking pattern.

**The diff algorithm (paragraph identity across edits):**
When a file is re-parsed, the index matches existing paragraphs to the new content:

1. Exact content hash match at the same position → same paragraph, no update needed (most common)
2. Exact content hash match at a different position → paragraph was reordered within the note, update `paragraph_index`
3. No exact match but high similarity (edit distance) at similar position → paragraph was edited, preserve UUID, update `content_hash` and `content_preview`, mark dirty for FTS5/HNSW
4. No match at all → new paragraph (assign new UUID) or deleted paragraph (remove from index)

**Scenario walkthrough — what happens to the index for each type of edit:**

**Content edit (user edits a paragraph's text):**
The paragraph's content hash changes. The diff algorithm matches it by position + similarity (step 3). The index preserves the UUID, updates `content_hash` and `content_preview`, and marks the paragraph dirty for FTS5/HNSW re-indexing. Any mentions pointing to this paragraph continue to resolve — the UUID is stable, and the mention chip shows the updated content on next render.

**New paragraph inserted (user presses Enter and writes a new paragraph):**
After re-parse, there's a new paragraph that doesn't match any existing content hash or position. The diff algorithm assigns it a new UUID (step 4). Paragraphs below the insertion point shift their `paragraph_index` values (step 2 — same content at a different position). FTS5/HNSW index the new paragraph. No mentions are affected — existing mentions point to UUIDs that are still present.

**Paragraph deleted (user removes a paragraph):**
After re-parse, an existing paragraph has no match in the new content (step 4). The index removes the paragraph row. FTS5/HNSW entries for that paragraph are deleted. If any mentions in other notes point to the deleted paragraph's UUID, those mentions become unresolved — the mention chip shows a tombstone or falls back to note-level display (see "What happens when a mentioned paragraph is deleted?" in Open Questions).

**Paragraph moved to another note (delete from source, insert into destination):**
This is two independent file edits:
1. *Source note re-parsed:* The moved paragraph is gone — step 4 removes it from the index. Its UUID, FTS5, and HNSW entries are deleted.
2. *Destination note re-parsed:* The moved paragraph appears as new content — step 4 assigns it a **new UUID**.

This means the paragraph gets a new identity after a cross-note move. Any mentions pointing to the old UUID in the source note become unresolved. This is the trade-off of file-based storage with no IDs in the markdown: the index can't know that a paragraph deleted from one file is the same paragraph inserted into another file. The content is just text.

**Mitigation for cross-note moves done in-app:** When the app itself performs a "Move to..." action, it can handle both files in a single pass — delete from source, insert into destination, and explicitly carry the UUID over in the index (skip step 4 for the destination, instead reuse the source UUID with the new `note_id`). This preserves mentions. Only external moves (e.g., user manually cuts text in another editor) lose the UUID.

**Paragraph split (user splits one paragraph into two by pressing Enter in the middle):**
After re-parse, one existing paragraph is gone and two new paragraphs appear. The diff algorithm matches one half by similarity (step 3, preserves the UUID) and treats the other half as new (step 4, new UUID). Which half keeps the UUID depends on which has higher similarity to the original — typically the first half. Mentions to the original UUID continue to resolve to whichever half kept it. Content in the other half is not reachable by the old mention.

**Paragraph merge (user merges two paragraphs into one by deleting the blank line between them):**
After re-parse, two existing paragraphs are gone and one new paragraph appears. The diff algorithm matches the merged paragraph to the one with highest similarity (step 3, preserves that UUID). The other paragraph's UUID is deleted (step 4). Mentions to the surviving UUID resolve to the merged content. Mentions to the deleted UUID become unresolved.

### Key Differences from v1

- **No SwiftData at all.** The source of truth is `.md` files. Structured queries go through the SQLite sidecar index.
- **Folder = directory.** No Folder model. The filesystem provides the hierarchy.
- **Note = file.** Metadata lives in YAML frontmatter.
- **Paragraph = text between blank lines.** Identity is maintained by the sidecar index, not by the file itself.
- **Everything is rebuildable.** Delete `.noto/` and the app rebuilds it from the markdown files. Only embeddings take time to regenerate.
- **Interoperable by default.** Other markdown apps can read and edit the same vault.

### What We Lose

Infinite nesting of content. A paragraph can't have sub-paragraphs. This is intentional — the outline's power was also its complexity. If someone needs hierarchy within a note, they can use markdown headings (`## Section`) and bullet lists (`- item`) — these are native markdown features that any renderer understands.

### What We Gain

Total portability. The user's notes aren't locked in a database. They're files they own, can version with git, sync with any service, edit with any tool, and keep forever.

---

## Relationship to v1

**v2 is a clean-sheet rewrite.** No code is reused from v1. The v1 packages (`NotoModels`, `NotoCore`, `NotoFTS5`, `NotoHNSW`, `NotoEmbedding`, `NotoDirtyTracker`, `NotoSearch`, `NotoTodayNotes`) remain in the repo as-is but are not imported by v2. v2 builds everything from scratch with new packages.

**Why not reuse:** The storage model is fundamentally different (markdown files + SQLite sidecar vs. SwiftData). Adapting v1 packages to the new architecture would mean gutting them anyway. Starting fresh is cleaner and avoids carrying v1 assumptions (Block-centric data model, SwiftData dependencies, outline editing logic) into a system that doesn't need them.

**What v1 informs:** The v1 brainstorms and research are still valuable as reference — particularly the search brainstorm (FTS5 setup, BM25 tuning, embedding model selection, HNSW configuration, hybrid ranking algorithm, dirty tracking patterns). The same concepts apply; the implementation is new.

---

## Architecture (Sketch)

Same principle as v1: **Swift packages with CLI-testable logic, thin UI shell.** But the storage layer shifts from SwiftData to **filesystem + SQLite sidecar**.

```
Packages/
  NotoVault/           # Vault manager: file I/O, directory watching, markdown parsing,
                       #   frontmatter read/write, paragraph extraction.
                       #   This is the new foundation — everything reads/writes through it.
  NotoIndex/           # SQLite sidecar index: paragraph identity, mention storage,
                       #   note metadata cache. Wraps raw SQLite C API.
                       #   Depends on: NotoVault
  NotoCore/            # NoteEditor (paragraph CRUD, move, reorder), DailyNoteBuilder,
                       #   FolderOps. Orchestrates vault writes + index updates.
                       #   Depends on: NotoVault, NotoIndex
  NotoMentions/        # Mention parsing (@[[...]] syntax), resolution, backlink queries,
                       #   tombstone handling. Depends on: NotoVault, NotoIndex
  NotoDirtyTracker/    # In-memory dirty set + dirty table for lazy flush to search indexes.
                       #   Depends on: NotoIndex
  NotoEmbedding/       # CoreML bge-small-en-v1.5 model + BERT tokenizer for embedding generation.
  NotoFTS5/            # FTS5 keyword search (virtual tables inside index.sqlite).
                       #   Depends on: NotoIndex
  NotoHNSW/            # HNSW vector index (usearch) for semantic search.
                       #   Depends on: NotoEmbedding
  NotoSearch/          # Hybrid search orchestrator: dual-level (note + paragraph) FTS5 + HNSW,
                       #   score normalization, ranking. Depends on: NotoIndex, NotoFTS5, NotoHNSW, NotoEmbedding

Noto/ (app target)
  Views/               # SwiftUI views (FolderList, NotesList, NoteEditor, DailyNote)
  Editor/              # Markdown editor — paragraph-aware text editing with live preview
  App/                 # Entry point, vault initialization
```

### Core Architectural Principle

Markdown files are the source of truth. SQLite is a derived index/cache. The app can function (degraded) with just the files. The index adds speed and features (mentions, search, paragraph identity) but is always rebuildable.

**`NotoVault`** — the filesystem layer:

- Opens/validates a vault directory
- Reads/writes `.md` files with frontmatter parsing
- Extracts paragraphs from markdown (splits on blank lines)
- Watches for file system changes (external edits)
- Provides a typed API: `Vault.readNote(at:) -> NoteFile`, `Vault.writeNote(_:)`, `Vault.listNotes(in:) -> [NoteFile]`

**`NotoIndex`** — the sidecar SQLite layer:

- Creates/maintains the `.noto/index.sqlite` database
- Paragraph identity resolution (content hash + position matching)
- Note metadata cache (fast queries without parsing every file)
- Full rebuild from vault scan

**`NotoMentions`** — mention lifecycle:

- Parsing `@[[...]]` syntax from paragraph text
- Resolving note name → note file, paragraph snippet → paragraph ID
- Backlink queries (which paragraphs mention this note/paragraph?)
- Tombstone handling for deleted/moved targets
- Re-resolution when files change

---

## UI Direction

### Navigation Structure

```
Tab Bar (or Sidebar on iPad/Mac)
  [Today]  [Notes]  [Search]

Today tab:
  → Opens today's daily note directly
  → Swipe left/right to navigate between days

Notes tab:
  → Folder list (top level)
  → Tap folder → Note list
  → Tap note → Note editor
  → "Daily Notes" folder auto-created, flat list of daily notes sorted by date

Search tab:
  → Search bar + results (document-level, expandable to paragraphs)
```

**Alternative: No tab bar.** Keep the v1 approach of a single screen with a bottom action bar (Today button + search). Folders are the root screen. This is simpler and avoids the tab bar eating screen space. The Today button provides the same one-tap access.

### Note Editor

The note editor is the core screen. It should feel like Apple Notes, Bear, or iA Writer — a clean writing surface.

- Title at the top (large, bold, editable)
- Paragraphs below as body text
- No bullets, no indentation (at least in v1 — markdown rendering can come later)
- Paragraph separator: subtle visual gap or a thin divider (to make the "paragraph as unit" concept visible without being intrusive)
- Long-press a paragraph → selection mode (blue highlight, action bar appears)
- Action bar: [Move to...] [Mention] [Copy] [Delete]

### Daily Note

The daily note is just a note editor with:

- Auto-generated title: "Mar 16, 2026"
- Date navigation: swipe or arrows to go to previous/next day
- Optional: a "Quick capture" bar at the top for one-line idea dumps (each becomes a paragraph)

### Mentions

When viewing a note that has backlinks (other notes referencing it):

- A "Referenced by" section at the bottom of the note
- Shows which notes mention this one, with a preview of the mentioning paragraph
- Tapping navigates to the source note

When a paragraph contains a mention:

- The mention renders as an inline tappable pill: `[@Project Alpha > API design thoughts]`
- Tapping the pill navigates to the referenced note/paragraph

---

## Open Design Questions

### 1. Paragraph granularity — what exactly is a paragraph?

Options:

- **Hard return:** Every press of Enter creates a new paragraph. Each paragraph has its own UUID, is independently moveable and mentionable. This is the most powerful model but might feel rigid.
- **Visual paragraph:** Blank-line-separated chunks of text. A paragraph can contain multiple lines (soft wraps). This feels more natural for prose writing.
- **Implicit:** The user doesn't think about paragraphs at all — they just write. The app uses NLP to detect paragraph boundaries. Fragile, unpredictable.

**Leaning toward:** Hard return. It mirrors the v1 block model (Enter = new block), makes the data model clean, and ensures every "line" is addressable. The UI just needs to make it feel like continuous text, not a list of discrete items.

### 2. Inline formatting

Since notes are markdown files, inline formatting is native — `**bold**`, `*italic*`, `[links](url)`, `# headings`, `- lists` all just work as standard markdown.

The question becomes: **how rich is the live rendering in the editor?**

Options:

- **Raw markdown:** Show the raw syntax (`**bold**`). User sees asterisks. Simple but ugly. Good for power users who think in markdown.
- **Live preview:** Render markdown inline as you type — bold text appears bold, headings appear large, etc. Hides the syntax characters. This is what Bear, Typora, and Obsidian's live preview mode do.
- **Hybrid (Obsidian-style):** Show rendered markdown, but reveal the raw syntax when the cursor is on that line. Best of both worlds but most complex to implement.

**Leaning toward:** Live preview for v1 (rendered markdown, no raw syntax visible). It's the most natural writing experience and aligns with the "feels like Apple Notes" goal. Raw mode can be a toggle for power users later.

### 3. Paragraph indentation / nesting

Do paragraphs within a note support any hierarchy?

Options:

- **Flat only:** Paragraphs are a flat list. No bullets, no sub-items. Maximum simplicity.
- **One level of indent:** Allow a paragraph to be "indented" under the previous one (like a bullet sub-item). Stored as `indentLevel: 0 or 1`. No deeper nesting.
- **Full nesting (back to outline):** This defeats the purpose of the pivot.

**Leaning toward:** Flat for v1. If users need bullets, they can use markdown (`- item`). Adding indent as an optional feature later is straightforward.

### 4. Folder depth

How deeply can folders nest?

Options:

- **One level only:** Folders are flat. Simple. Sufficient for most personal use.
- **Two levels:** Folders can contain sub-folders. Covers most organizational needs without complexity.
- **Unlimited:** Like a file system. Maximum flexibility but adds complexity.

**Leaning toward:** Two levels. Covers "Work > Projects" and "Personal > Hobbies" patterns without becoming a file manager.

### 5. What happens when a mentioned paragraph is deleted?

Options:

- **Mention becomes a tombstone:** Shows "[deleted paragraph]" with a strikethrough. The mention link is preserved but unresolvable.
- **Mention is removed:** The inline mention disappears from the source paragraph. Content text around it is preserved.
- **Soft delete + warning:** The paragraph is archived, and mentions show it as "[archived]" with an option to restore.

**Leaning toward:** Tombstone. It's honest about what happened and doesn't silently alter the source paragraph.

### 6. ~~Vault location and access~~ DECIDED

**Decision:** Default to the device's local storage ("On My iPhone" / "On My iPad") with a root folder called `Noto/`. This maps to the app's Documents directory, visible in the Files app under "On My iPhone > Noto". The sidecar index (`.noto/`) lives inside the same `Noto/` folder alongside the markdown files. No iCloud sync for now — local-first, simple.

### 8. What about images and attachments?

Markdown supports image references (`![alt](path)`). If the user pastes an image into a note:

Options:

- **Store in a local `attachments/` folder:** `Noto/attachments/image-2026-03-16-1.png`, referenced as `![](attachments/image-2026-03-16-1.png)`. Standard approach (Obsidian does this).
- **Per-note attachment folder:** `Noto/Projects/Project Alpha/` contains both the `.md` file and its images. Cleaner per-note, but more directories.
- **Defer to v2:** Text-only for now. Images can come later.

**Leaning toward:** `attachments/` folder approach, deferred to after core features work. Text-first.

---

## Implementation Priority

### Phase 1 — Vault + Markdown Foundation + Daily Note

- NotoVault package: file I/O, markdown parsing, frontmatter handling, directory watching
- NotoIndex package: SQLite sidecar, paragraph identity, note metadata cache
- Vault initialization (create `.noto/`, verify directory structure)
- CRUD operations (create/read/update/delete notes as `.md` files, paragraph extraction)
- Daily note auto-creation (`Daily Notes/YYYY-MM-DD.md`)
- Basic note editor UI (title + paragraphs, markdown live preview)
- Folder browsing UI (directories as folders)
- Today button / entry point

### Phase 2 — Paragraph Mobility

- Long-press paragraph selection
- "Move to..." sheet with note picker
- Move operation (remove from source + insert in destination)
- Ghost/tombstone for moved paragraphs
- Move history tracking

### Phase 3 — Mentions

- @ trigger and mention picker (note search)
- Mention inline rendering (tappable pill)
- Paragraph-level mention targeting
- Backlinks panel on notes
- Live cascade rendering (mentions always show current paragraph text)

### Phase 4 — Hybrid Search

- FTS5 keyword indexing (dual-level: paragraph + note)
- Embedding generation (dual-level: paragraph + note)
- HNSW vector index
- Add document-level aggregation
- Search UI with dual-level results (note + paragraph)

### Phase 5 — Polish + Advanced

- Markdown rendering in paragraphs
- Paragraph indentation (optional bullet lists)
- Folder customization (icons, colors)
- AI chat integration (grounded on paragraph search)
- Multi-device sync

---

## Risks and Considerations

**Risk: Paragraphs are too granular.** If every Enter creates a new paragraph, users might end up with hundreds of tiny paragraphs per note. Mitigation: the UI should make paragraphs feel like natural text, not a numbered list. Paragraph IDs are invisible — users don't know they exist unless they use move/mention.

**Risk: Moving paragraphs creates orphaned context.** A paragraph that made sense in Note A might be confusing in Note B without surrounding context. Mitigation: the move UI could show surrounding paragraphs for context before confirming, and the ghost in the source note links back.

**Risk: Mention resolution is complex.** Paragraphs can be moved, edited, merged, split. Mentions point to paragraph UUIDs, so edits are handled automatically (the UUID stays stable, live cascade shows the new content). Moves need to update the mention's target note in the index. Deletes need to mark the mention as unresolved. Splits/merges are the hardest case — the original UUID goes to one of the halves, and any mention to the other half is lost. Defer split/merge handling to later.

**Risk: Losing the outline's power.** Some users genuinely want deep nesting. Mitigation: this is a deliberate trade-off. The app is choosing clarity and simplicity over structural flexibility. Users who need outlining have Logseq, Roam, Workflowy. Noto v2 is for people who want a note app that's smarter about connecting and moving content.

**Risk: Paragraph identity is fragile with file-based storage.** Unlike a database where rows have stable IDs, paragraphs in a markdown file have no inherent identity. External edits (rewriting a paragraph, reordering paragraphs, merging/splitting) can break the sidecar index's mapping. Mitigation: the index uses fuzzy matching (content similarity + position) to re-associate paragraphs after edits. Mentions degrade gracefully (show last-known text) when a target can't be resolved. The system is designed to be "eventually consistent" — a full re-index always restores correctness.

**Risk: External editors break mention syntax.** If a user edits a note in VS Code and accidentally modifies an `@[[...]]` mention, the mention breaks. Mitigation: the mention syntax is designed to be human-readable and unlikely to be accidentally edited. The app can detect malformed mentions on file reload and flag them. Also, the `@[[]]` syntax is compatible with Obsidian, so users of that ecosystem will already be familiar with it.

**Risk: Performance of file-based storage at scale.** Reading/writing individual files is slower than database operations at high volume (10,000+ notes). Mitigation: the sidecar index caches all metadata needed for browsing and search. File I/O only happens when opening a specific note for editing or when syncing after external changes. The index makes list views and search instant; only the editor hits the filesystem.

---

## Pillar 5: AI-Operability

Every action in Noto — creating notes, creating folders, editing content, moving paragraphs, searching, reading — must be performable programmatically via a CLI, MCP server, or tool call interface. The app is not just for human users; an AI agent should be able to operate on the vault as a first-class participant.

**Why this matters:** Markdown files on disk already make the vault readable/writable by any program. But structured operations (create note in folder, search by meaning, resolve mentions) need a proper API surface beyond raw file manipulation. Exposing these as CLI commands or MCP tools means an AI agent can:

- Create and organize notes on behalf of the user
- Search across the vault and surface relevant content
- Move paragraphs between notes programmatically
- Read and summarize note content
- Build automations and workflows on top of the vault

**Design principle:** Every operation — vault management, note editing, search, mentions — must be operable by an AI agent via CLI, MCP server, or API. If a human can do it in the UI, an agent can do it via a tool call. No operation is UI-only. The vault's file-based storage makes this natural — the CLI/MCP layer is a thin wrapper around the same operations the app performs internally.

**Core operations for AI agents:**

*Vault operations (map directly to filesystem — no custom interface needed on macOS):*
- **Create folder** — `mkdir` / `FileManager.createDirectory`
- **Create note** — write a `.md` file
- **Delete note/folder** — remove file/directory
- **Move note** — move file between directories
- **Read note** — read file contents
- **List folder** — list directory contents

*Edit operations (require a structured interface — the agent edits note content):*
- **Append** — add content to the end of a note. Safest and simplest. The AI suggests text and it lands at the bottom. No risk of clobbering existing content.
- **Insert at line** — add content at a specific line number or after a specific heading/paragraph. Enables the AI to place content precisely (e.g., add a bullet under "Shopping List", insert a paragraph after the introduction). Requires the agent to know the note's structure — read first, then insert.
- **Replace range** — swap out a line range or paragraph with new content. This is how the AI applies suggested edits — "replace lines 5-8 with this revised version." The most powerful but also the most dangerous operation; the agent must match the exact range to avoid unintended overwrites.

*On iOS:* These edit operations would be exposed as MCP tools running inside the app. The MCP server calls the same `MarkdownNoteStore` methods the UI uses. On macOS or via terminal, vault operations work with standard shell commands; edit operations could use a lightweight CLI that reads/modifies the `.md` files directly (like `sed` but with line-aware markdown operations).

## Summary

Noto v2 trades the outline's infinite structure for a more intuitive notes-and-folders model backed by **plain markdown files on disk**, then adds five superpowers that most note apps lack:

1. **Daily note** as the default writing surface
2. **Per-line mentions** — live references to specific paragraphs across notes using `@[[Note#id]]` syntax, always showing current content
3. **Hybrid search** — find anything by keyword or meaning, at both paragraph and document level
4. **Markdown files as storage** — notes are portable `.md` files, not locked in a database
5. **AI-operability** — every operation (create, read, edit, search, organize) is accessible via CLI, MCP server, or API, so AI agents can operate on the vault as first-class participants

The storage shift from SwiftData to filesystem + SQLite sidecar is the biggest architectural change. It trades the convenience of a managed database for total portability, interoperability (Obsidian, iA Writer, git), and user ownership of their data. The sidecar index provides the structured query capabilities (paragraph identity, mentions, search) that files alone can't offer, while remaining fully rebuildable from the markdown files.

The existing search infrastructure (FTS5, embeddings, HNSW, dirty tracking) transfers almost entirely. The editing experience gets simpler (no outline tree management). The hard problems are paragraph identity in a file-based world, mention resolution across moves, and keeping the sidecar index in sync with external edits.
