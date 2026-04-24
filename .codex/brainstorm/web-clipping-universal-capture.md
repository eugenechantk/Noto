# Universal Capture and Source Notes

Date: 2026-04-20

## Goal

Noto should become the durable home for things Eugene reads, watches, listens to, and highlights.

The target behavior is:

- One markdown page per source inside a user-chosen vault directory.
- Each source page contains highlights.
- Each source page contains full content when it is legally and technically available.
- Sources without full content, such as many Kindle books or podcast episodes, still get useful source pages with highlights, metadata, links, timestamps, and a clear capture status.
- Imported pages stay editable as normal Noto notes, without the sync process clobbering Eugene's own notes.

This is broader than "web clipping." The better product concept is a source-note system with multiple capture adapters.

## Prior Research Summary

Existing notes reviewed:

- `.claude/Noto v2/Clipper-analysis.md`
- `.claude/research-obsidian-clipper.md`

Those docs correctly identify:

- Defuddle is the extraction engine worth reusing rather than rebuilding.
- Obsidian Web Clipper is useful as reference architecture, especially for browser extension structure, templates, and persisted highlights.
- A Safari extension is valuable for in-page clipping and highlighting, but it is not the only capture path.
- A share extension or direct importer is a simpler first surface than a full browser extension.

One update: the prior Obsidian Clipper note referenced version 1.2.1. GitHub currently shows Obsidian Web Clipper latest release 1.5.1 on 2026-04-15.

## Current External Capabilities

### Readwise Highlights API

Readwise API v2 supports:

- `GET /api/v2/export/` for grouped highlight export.
- `updatedAfter` for incremental sync.
- `includeDeleted=true` for deletion-aware sync.
- Pagination through `pageCursor`.
- Source-level fields such as `user_book_id`, `title`, `author`, `category`, `source`, `source_url`, `unique_url`, `asin`, `external_id`, and `readwise_url`.
- Highlight-level fields such as `id`, `text`, `note`, `location`, `location_type`, `highlighted_at`, `url`, `external_id`, `tags`, and `readwise_url`.

Important constraint: this API is fundamentally highlight-centric. It is excellent for Kindle, Reader highlights, podcast highlights, and cross-source highlight backfill, but it does not provide full source text for most sources.

### Readwise Reader API

Reader API v3 supports:

- `POST /api/v3/save/` for adding documents to Reader.
- `GET /api/v3/list/` for listing documents.
- `updatedAfter`, `location`, `category`, `tag`, pagination through `pageCursor`.
- `withHtmlContent=true` to include `html_content`.
- `withRawSourceUrl=true` to include a temporary raw source file URL when available.

This matters because Reader can be a full-content source for articles, tweets, videos, PDFs, EPUBs, emails, and RSS documents where Reader has retained HTML or raw source. It should be checked before re-scraping the open web.

### Readwise Webhooks

Readwise custom webhooks support:

- `readwise.highlight.created`
- `reader.any_document.created`
- `reader.feed_document.created`
- `reader.non_feed_document.created`
- document movement/tag/read-state events such as archived, finished, moved to later, and shortlisted

Webhook payloads include metadata and a shared secret, but the document payload example has `content: null`, and highlight payloads only include the highlight event. Treat webhooks as a notification trigger, not as the source of truth. After receiving a webhook, the sync process should call the Readwise/Reader APIs to fetch canonical data.

### Defuddle

Defuddle supports URL or HTML to cleaned HTML/Markdown, metadata extraction, browser usage, Node usage, and different bundles:

- Core browser bundle.
- Full bundle with Markdown conversion and richer parsing.
- Node bundle for DOM implementations like `linkedom` or JSDOM.

It also has async extraction behavior for pages where local HTML does not contain usable content. Current docs mention FxTwitter fallback for X/Twitter content, which is useful but should be privacy-controlled because it can call third-party services.

### Obsidian Web Clipper

Obsidian Web Clipper remains the best reference for:

- Browser extension architecture.
- Content scripts plus background service worker.
- In-page highlights stored by URL and XPath/range.
- Template variables, filters, and source-specific output rules.
- Clipboard plus custom URI handoff into the native app.

For Noto, cloning the whole feature surface first would be too much. Reuse the ideas and extraction stack, but design the source-note model around Noto's vault.

## Recommended Product Model

Create a Noto concept called a source note.

A source note is just a normal markdown file, but it has enough frontmatter, minimal hidden boundary tags, and sidecar sync state to make imports idempotent without forcing visible body sections.

Recommended directory shape:

```text
<vault>/
  Captures/
    Article Title.md
    Podcast Episode.md
    Tweet Thread.md
```

The default root is `Captures/`, created by the CLI on first write if it does not already exist. The configured root can still be any directory Eugene chooses. Keep it flat by default. Avoid category subfolders; source type belongs in frontmatter and search/filter UI, not in the filesystem hierarchy.

## Source Note Template

Draft format:

```markdown
---
id: 2D51D792-8D67-4DF6-A6A2-3D9DB76696D7
created: 2026-04-20T10:00:00Z
updated: 2026-04-20T10:00:00Z
type: source
source_kind: article
capture_status: full
canonical_key: reader:01gwfvp9pyaabcdgmx14f6ha0
source_url: https://example.com/article
reader_document_id: 01gwfvp9pyaabcdgmx14f6ha0
reader_url: https://read.readwise.io/read/01gwfvp9pyaabcdgmx14f6ha0
reader_location: archive
readwise_user_book_id: 123456
readwise_url: https://read.readwise.io/read/01gwfvp9pyaabcdgmx14f6ha0
readwise_bookreview_url: https://readwise.io/bookreview/123456
author: Jane Doe
site_name: Example
published: 2026-04-18
tags:
  - imported/reader
  - imported/readwise
  - content-creation
---

# Article Title

Personal notes can go anywhere outside the generated block.

Source: [Example](https://example.com/article)
Readwise: [Open in Reader](https://read.readwise.io/read/01gwfvp9pyaabcdgmx14f6ha0)
Captured: 2026-04-20T10:00:00Z

<!-- noto:highlights:start -->
> Highlight text.
>
> Note: My annotation.
>
> Location: 42
<!-- noto:highlights:end -->

<!-- noto:content:start -->
Full extracted markdown goes here.
<!-- noto:content:end -->
```

No required visible body sections. The required body markers are the hidden comments around generated highlights and generated full content.

Inside the generated block, body-visible metadata should stay minimal:

- Source link.
- Readwise link, only if one exists.
- Captured date.

Everything else, including capture status, source kind, Reader ids, Reader location, Reader tags, author, site name, and published date, belongs in frontmatter or hidden sync state rather than the main body text.

Why the minimal tags are worth it:

- Frontmatter is importer-owned for source identity, metadata, and timestamps.
- The generated highlights block is importer-owned and can be safely replaced by Readwise-highlight sync.
- The generated content block is importer-owned and can be safely replaced by Reader/full-content sync.
- Everything outside those blocks is user-owned and never rewritten by the importer.
- A hidden sidecar sync state stores source-to-file mappings, upstream highlight IDs, generated block hash, and fetch cursors.
- If markers are missing, recreate the relevant generated block below the title and keep the rest of the note intact.
- If a generated block was edited by hand and its hash no longer matches the sidecar, keep a backup of the edited block in sync state or append a conflict note before replacing it.

This is the smallest reliable rewrite surface: four hidden comments, no required headings, and no machine-owned prose outside the highlight/content blocks.

## Frontmatter Compatibility Issue

Noto currently has a small frontmatter inconsistency:

- `Noto/Storage/MarkdownNoteStore.swift` creates and updates `updated:`.
- `Packages/NotoVault/Sources/NotoVault/Frontmatter.swift` serializes/parses `modified:`.

Decision: use `updated:` for source notes and app-generated frontmatter. Update package parsing/serialization to accept both `updated:` and legacy `modified:`, but emit `updated:`. Source notes will need extra keys, so this is the right time to make frontmatter handling more deliberate.

## Identity and Deduping

Use a stable canonical key per source. Priority order:

1. Reader document id: `reader:<id>`
2. Readwise user book id: `readwise-book:<user_book_id>`
3. Readwise/Reader external id: `external:<source>:<external_id>`
4. Canonical URL: `url:<normalized source_url>`
5. Kindle ASIN plus title/author: `asin:<asin>`
6. Fallback title/author/source-kind hash.

The importer should upsert by canonical key, not by filename. Filenames can change if titles improve.

Keep a hidden sync state file outside the source-note directory, for example:

```text
<vault>/.noto/sync/readwise.json
```

This can store cursors, last sync timestamps, source-to-file mappings, and failure state. Noto's directory loader already skips hidden files.

## Capture Matrix

| Source | Highlights | Full content path | Expected status |
| --- | --- | --- | --- |
| Reader web article | Readwise export or Reader docs | Reader `html_content`, raw source URL, then Defuddle fallback | Often full |
| Reader tweet/X thread | Readwise export or Reader docs | Reader HTML/raw source, Defuddle async/Twitter extractor fallback | Sometimes full |
| YouTube | Readwise export or Reader docs | Reader video doc data, Defuddle transcript support, YouTube transcript fallback | Sometimes transcript |
| Kindle book | Readwise export | Not available unless user supplies EPUB/PDF or external source | Highlights only |
| Podcast | Readwise export | Not available unless transcript provider/source URL available | Highlights plus timestamps |
| PDF/EPUB in Reader | Reader docs | Reader raw source URL or html content when available | Sometimes full |
| Newsletter/email | Reader docs | Reader html content | Often full |

For anything not full, the page should still be valuable. Do not hide failure. Show `capture_status: highlights_only` or `metadata_only`, and include the reason.

## Sync Pipeline

### Initial Backfill

Implemented first pass: `Packages/NotoReadwiseSync` contains a local Swift CLI named `noto-readwise-sync`.

The CLI backfills by fetching items from Readwise/Reader, rendering one flat source note per source into the configured source directory, and recording source-to-file mappings in `<vault>/.noto/sync/readwise.json` so later runs update existing notes instead of duplicating them.

Current modes:

```bash
# Readwise highlights-only sources
noto-readwise-sync --vault "/path/to/Noto"

# Reader saved documents with full Reader content
noto-readwise-sync --vault "/path/to/Noto" --reader
```

For local testing with the token stored in macOS Keychain:

```bash
READWISE_TOKEN="$(security find-generic-password -s "com.noto.readwise" -a "readwise-token" -w)" \
swift run noto-readwise-sync \
  --vault "/Users/eugenechan/Library/Mobile Documents/com~apple~CloudDocs/Noto" \
  --reader
```

Implemented Readwise mode:

1. Reads token from `--token` or `READWISE_TOKEN`.
2. Fetches Readwise export API v2.
3. Creates or updates one source note per Readwise source.
4. Writes highlights into the generated highlights block.
5. Leaves the generated content block empty when no full content is available.
6. Skips deleted upstream sources and deleted upstream highlights.

Implemented Reader mode:

1. Reads token from `--token` or `READWISE_TOKEN`.
2. Fetches Reader API v3 list with full HTML content enabled.
3. Converts Reader `html_content` to markdown.
4. Creates or updates one source note per top-level Reader document.
5. Writes full article content into the generated content block.
6. Unless `--no-reader-highlights` is passed, also fetches Readwise export API v2 and joins matching highlights where `ReadwiseBook.source == "reader"` and `ReadwiseBook.external_id == ReaderDocument.id`.
7. Writes joined Readwise highlights into the generated highlights block.

Matching and update behavior:

- Reader notes use `canonical_key: "reader:<reader_document_id>"`.
- Readwise-only notes use `canonical_key: "readwise-book:<readwise_user_book_id>"`.
- Readwise sources that came from Reader do not get their own separate `readwise-book:*` note. When `ReadwiseBook.source == "reader"` and `ReadwiseBook.external_id == ReaderDocument.id`, they reconcile onto the Reader identity and update the same `reader:<reader_document_id>` note.
- On later runs, the CLI first checks `<vault>/.noto/sync/readwise.json`.
- If the mapping is missing, it scans existing markdown files for `canonical_key`.
- If a match exists, it replaces only the generated highlights/content blocks and refreshes frontmatter.
- If no match exists, it creates a new markdown file under `Captures/` by default, or the directory passed through `--source-dir`.

Sync state currently stored in `<vault>/.noto/sync/readwise.json`:

- `lastSuccessfulSyncAt`: last successful Readwise export sync timestamp
- `lastSuccessfulReaderSyncAt`: last successful Reader sync timestamp
- `sources[canonical_key]`:
  - `relativePath`
  - `noteID`
  - `generatedBlockHash`
  - `readerDocumentID`
  - `readwiseUserBookID`
  - `updatedAt`

How incremental sync should work:

1. Use Reader API `updatedAfter=<lastSuccessfulReaderSyncAt>` so only changed Reader documents are fetched.
2. Use Readwise export API `updatedAfter=<lastSuccessfulSyncAt>` so only changed highlighted sources are fetched.
3. For each returned item, compute the canonical key:
   - `reader:<reader_document_id>` for Reader documents
   - `reader:<external_id>` for Readwise items whose `source == "reader"`
   - `readwise-book:<user_book_id>` for Readwise-only items
4. Use sync state to find the existing local note path quickly.
5. If the mapping is missing, fall back to scanning frontmatter for `canonical_key`.
6. Replace only importer-owned blocks:
   - highlights block from Readwise
   - content block from Reader
   - importer-owned frontmatter fields
7. Save the new successful sync timestamps back to `readwise.json`.

This keeps steady-state sync proportional to changed upstream items rather than reprocessing the full library on every run.

Useful backfill controls:

```bash
# Test only N fetched items
--limit 10

# Import one Reader document
--reader-id 01kkapgxc8e1pm73gfq1vfj6fq

# Fetch and plan without writing files
--dry-run

# Reader saved articles only
--reader --reader-category article

# Reader documents in a specific location
--reader --reader-location archive

# Reader articles with a tag. Repeat --reader-tag up to 5 times; Reader requires all listed tags.
--reader --reader-category article --reader-tag content-creation

# Incremental API fetch by upstream updated timestamp
--updated-after 2026-04-01T00:00:00Z
```

Reader tag filtering:

- `--reader-tag <tag>` maps directly to Reader API `tag=<tag>` on `GET /api/v3/list/`.
- Repeat `--reader-tag` up to 5 times.
- Reader treats repeated tags as an AND filter: returned documents must have all listed tags.
- Use `--reader-category article` with `--reader-tag` when the desired backfill is only tagged web articles, not tagged tweets, PDFs, videos, notes, or other Reader document types.
- The CLI still writes all Reader tag names found on each imported document into source-note frontmatter `tags:`.

Example:

```bash
READWISE_TOKEN="$(security find-generic-password -s "com.noto.readwise" -a "readwise-token" -w)" \
swift run noto-readwise-sync \
  --vault "/Users/eugenechan/Library/Mobile Documents/com~apple~CloudDocs/Noto" \
  --reader \
  --reader-category article \
  --reader-tag content-creation \
  --limit 5 \
  --dry-run
```

URL behavior for joined Reader plus Readwise notes:

- `reader_url` stores the Reader document URL.
- `readwise_url` also points to the Reader document URL, because Reader has the richer source context.
- `readwise_bookreview_url` preserves the Readwise bookreview URL for debugging and future sync needs.
- The note body no longer shows generated metadata lines such as `Source`, `Readwise`, or `Captured`; those fields live in frontmatter only.

Important caveat: full content currently comes from Reader only. Highlights come from Readwise export. The richest backfill path is therefore Reader mode, because it can produce notes with both full content and highlights when the Reader document has a matching Readwise highlighted entity. Readwise-only mode remains necessary for Kindle, podcasts, books, and any source where Reader has no full document.

Secret storage model:

- The Readwise token must never be stored in the vault, frontmatter, `.noto/sync/readwise.json`, `.obsidian/`, or any other iCloud-synced markdown/config file.
- macOS should store the token in Keychain. The current local CLI already uses:
  - service: `com.noto.readwise`
  - account: `readwise-token`
- iPhone and iPad should store the token in the iOS Keychain through Noto app settings.
- The vault stores only sync state, not secrets.
- Cross-device availability should come from secure per-device storage first. If iCloud Keychain propagation works for the chosen keychain item configuration, treat that as a UX improvement, not a hard dependency.

Recommended product behavior:

1. Noto settings expose `Set Token`, `Test Connection`, and `Sync Now`.
2. The token is written to secure platform storage:
   - macOS Keychain on macOS
   - iOS Keychain on iPhone/iPad
3. Sync code reads the token from secure storage at runtime.
4. Source notes and sync-state files remain portable and plain-text, with no embedded secrets.

Still planned:

1. Add automatic pagination coverage tests against larger fixture sets.
2. Use Reader raw source URL when `html_content` is missing.
3. Add Defuddle/direct web extraction fallback for sources that Reader cannot hydrate.
4. Add incremental sync in Noto itself through app-launch sync plus a settings action.

### Incremental Sync

Start with app-launch sync plus an explicit settings action, but no periodic polling:

1. Run sync when Noto launches or opens.
2. Also allow the user to tap `Sync now` in Noto settings.
3. Call Readwise export with `updatedAfter=<last_successful_sync>`.
4. Call Reader list with `updatedAfter=<last_successful_sync>`.
5. Replace the generated highlights block and/or generated content block for affected source notes.
6. If `includeDeleted=true` is enabled, remove deleted upstream highlights from the generated highlights block while preserving content and all user-owned markdown outside generated blocks.

This keeps the product simple, avoids continuous background polling, and still gives predictable incremental updates without a server.

Execution model:

- The sync pipeline should run off the main thread: token lookup, network calls, JSON decoding, HTML-to-Markdown conversion, note rendering, and file writes are background work.
- The UI should not block on sync completion. On app launch, Noto should render from the local vault first, then let sync run in the background.
- Sync should write files into the vault and update `.noto/sync/readwise.json`; it should not manually mutate note-list UI state item-by-item.
- Noto already observes vault filesystem changes for note-list/sidebar refresh. Sync should rely on that existing watcher path so newly created or updated source notes appear through normal vault observation.
- The only direct UI state sync needs is lightweight status such as `syncing`, `last synced`, and `error`.

### Webhooks Later

Use webhooks only when there is a hosted or always-on sync process:

1. Receive event.
2. Verify the secret.
3. Queue a sync for the affected document/highlight.
4. Fetch canonical state through API.
5. Upsert source note.

This gives immediacy without trusting webhook payloads as complete content.

## Full Content Hydration

Hydration priority:

1. Reader `html_content`, if present.
2. Reader raw source URL, if present and fetchable.
3. Original `source_url`, fetched directly.
4. Defuddle parse from fetched HTML.
5. Site-specific extraction only where needed.
6. Mark as `highlights_only` with a reason if no full content can be obtained.

Use Defuddle in Node/TypeScript as a later fallback for pages Reader cannot hydrate. The first sync implementation already exists as a Swift package in this repo; do not move core sync orchestration into app UI code.

Privacy note: Defuddle async extractors can call third-party services for some client-rendered pages. This should be a setting, especially for private reading material.

## Implementation Options

### Option A: Local Sync CLI First

Use the existing Swift sync package and thin CLI wrapper:

- `Packages/NotoReadwiseSync` owns sync logic:
  - Reader / Readwise API clients
  - canonical-key reconciliation
  - incremental cursor handling
  - source-note rendering
  - sync-state read/write
  - highlight/delete reconciliation rules
- `Sources/noto-readwise-sync` is only a CLI shell over the package.
- The package writes markdown files directly to the vault and stores sync state in `<vault>/.noto/sync/readwise.json`.

Recommendation: start here.

Reasons:

- Fastest way to validate the source-note format.
- Avoids iOS background execution limits.
- Avoids shipping token UI and OAuth immediately.
- Easy to test against sample fixtures.
- The same package can later be embedded in macOS/iOS Noto without duplicating sync behavior.

### Option B: Native Noto Importer

Build token storage, sync settings, and import directly into Noto, but keep sync orchestration in `Packages/NotoReadwiseSync`.

The app should only own:

- secure token storage access
- settings UI
- launch / `Sync now` triggers
- sync status and errors

The package should continue to own:

- API calls
- merge logic
- rendering and file writes
- sync-state updates

This is the right long-term experience, especially on macOS. It is more product-complete but slower because it needs UI, secure token storage, error handling, and launch-triggered background behavior.

### Option C: Hosted Sync Service

Use webhooks and a small service to sync into a cloud-accessible vault or bridge.

This is powerful but prematurely complex unless Noto already has account/cloud infrastructure.

### Option D: Safari Extension / Web Clipper

Build a browser extension for first-party capture:

- Clip current page.
- Persist page highlights.
- Use Defuddle in content scripts.
- Hand off to Noto via URL scheme, share extension, or direct file access on macOS.

This is the right direct-capture surface later, but it does not solve Kindle/podcast/Reader backfill. It should come after the source-note model is proven.

## Recommended Roadmap

### Phase 1: Source Note Format and Local Backfill

- Add a deterministic source-note renderer.
- Build a local import command for Readwise export.
- Write one note per source with highlights.
- Preserve manual edits by rewriting only the minimal generated highlights/content blocks.
- Support a configured flat source directory.
- Add fixture tests for books, articles, tweets, podcasts, and duplicate titles.

Success: all existing Readwise highlights become source notes in the vault.

### Phase 2: Reader Full Content Hydration

- Pull Reader documents with `withHtmlContent=true` and `withRawSourceUrl=true`.
- Join Reader documents to Readwise highlight groups.
- Convert Reader `html_content` to Markdown directly first; add Defuddle only as a fallback for sources Reader cannot hydrate.
- Store capture status and hydration errors.
- Avoid duplicate notes for the same article/tweet/video.

Success: Reader articles and many tweets/videos have full content plus highlights.

### Phase 3: Incremental Sync

- Keep incremental sync orchestration in `Packages/NotoReadwiseSync`.
- Store sync state.
- Sync when the app launches/opens, and also when the user taps `Sync now` in settings, using `updatedAfter`.
- Support deleted highlights through `includeDeleted=true`.
- Replace only the generated highlights/content blocks.
- Preserve all markdown outside generated blocks.
- Add retry/failure reporting.

Success: regular sync keeps source notes current without overwriting manual notes.

### Phase 4: Native Product UI

- Add Noto settings for Readwise token and source directory.
- Use the sync package from the app instead of reimplementing sync logic in the app target.
- Show sync status and failures.
- Let Eugene run sync manually.
- Add macOS scheduled sync if useful.

Success: the local CLI behavior becomes part of Noto.

### Phase 5: Direct Web Clipper

- Add Safari extension/share extension.
- Use Defuddle directly for current page extraction.
- Add in-page highlight capture if worth the complexity.
- Save to the same source-note format.

Success: new web reading can go directly into Noto even without Reader.

## Product Decisions To Make

1. Source directory default: `Captures/`, flat.
2. Manual notes policy: no required visible body sections; frontmatter plus hidden generated highlight/content blocks are importer-owned, all markdown outside those blocks is user-owned.
3. Full content legality/privacy: recommend storing what APIs or open pages provide, with clear `capture_status`.
4. Third-party extraction: recommend opt-in for Defuddle async fallbacks.
5. Timestamp frontmatter: use `updated:` while accepting `modified:` during migration.
6. Generated highlight style: recommend blockquotes with notes/location metadata first; add inline `==highlight==` only when source offsets map reliably into full content.

## Strong Recommendation

Build the source-note importer before building a browser clipper.

The user value is not "clip this page." The user value is "my read/highlighted universe is in my vault." Readwise/Reader import solves the largest backlog and forces the right durable data model. The Safari clipper should reuse that model later instead of inventing its own note shape.
