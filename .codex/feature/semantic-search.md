# Feature: Semantic Search (hybrid keyword + embedding search)

Full design rationale: `.claude/brainstorm/semantic-search-plan.md`. Spike results: `.claude/spikes/embedding-conversion-spike-20260610.md`. Branch: `feature/semantic-search` (worktree).

## User Story

As a Noto user with notes in multiple languages, I can search by meaning — "rent negotiation" finds my 房东续租 note — not just by keyword, from the existing search sheet, fully on-device.

## User Flow

1. User opens the search sheet (unchanged) and types a query.
2. Keyword results appear instantly on each keystroke (existing FTS path, unchanged).
3. ≥3 chars: after a short debounce the semantic leg runs (embed query → cosine scan → RRF-fuse with keyword results) and the single blended list updates stably.
4. Index maintenance is invisible: notes are embedded incrementally as they change, derived from the existing FTS index lifecycle. Settings shows semantic index stats and offers rebuild.

## Success Criteria

- SC1: Chunker splits `SearchDocument`s into chunks with contextual headers (`title > heading`), token-capped (~400 est. tokens), whole-note single chunk when small; stable chunk IDs; deterministic.
- SC2: SemanticIndexStore persists chunks + fp32 vectors in `semantic.sqlite` (separate from `search.sqlite` so FTS destroy/rebuild never wipes embeddings); generation counter bumps on mutation.
- SC3: SemanticIndexer refresh is incremental: only changed notes re-extracted, only changed chunks re-embedded (hash includes model version); deleted notes purged; model-version bump re-embeds everything; missing `search.sqlite` → graceful no-op.
- SC4: SemanticSearcher returns exact cosine top-k over all stored vectors (verified vs naive impl); cache invalidates on store generation change.
- SC5: RRF fusion (k=60) merges keyword + semantic note-level rankings; semantic-only notes get a synthesized result with chunk snippet + lineStart; dedupe by noteID; keyword-only behavior unchanged when semantic is empty/unavailable.
- SC6: GraniteTokenizer matches Python tokenizer exactly on 20 golden fixtures (EN/ZH/JA/KO/emoji/truncation).
- SC7: GraniteEmbedder (tokenize → CoreML → 384-d vector) matches Python reference vectors cosine ≥ 0.999 on fixture texts; loads compiled mlmodelc in app builds and compiles mlpackage under `swift test`.
- SC8: End to end in the search UI: a query with NO keyword overlap surfaces the semantically relevant note (e.g. EN query → ZH note) in the blended list; keyword results still appear instantly; index updates after editing a note.
- SC9: All existing NotoSearch/app tests keep passing.

## Test Strategy

Package-level Swift Testing with a deterministic fake embedder for all NotoSearch logic (SC1–SC5); NotoEmbedding golden-fixture tests against Python-generated references (SC6–SC7); simulator E2E + visual evidence audit for SC8.

## Tests

### NotoEmbedding (package)
- `GraniteTokenizerTests` — 20 golden cases exact-match (SC6), truncation, determinism.
- `GraniteEmbedderTests` — golden vectors cosine ≥ 0.999 (SC7), pad/truncate shapes.

### NotoSearch (package)
- `SemanticChunkerTests` — header format, whole-note vs per-section, token cap split, CJK estimation, stable IDs, empty/tiny notes (SC1).
- `SemanticIndexStoreTests` — round-trip, replaceNote, deleteNote, vector blob encode/decode, generation bump, destroy (SC2).
- `SemanticIndexerTests` — incremental refresh w/ fake embedder + temp vault: new/changed/deleted/unchanged notes, embed-call counting (only changed chunks), model-version bump, no search.sqlite no-op (SC3).
- `SemanticSearcherTests` — top-k matches naive cosine on random vectors, cache invalidation on generation change, empty index (SC4).
- `HybridSearchFusionTests` — RRF ordering, semantic-only synthesis, dedupe, keyword-only passthrough, limit (SC5).

## Implementation Details

- `Packages/NotoEmbedding`: vendored swift-transformers BPE tokenizer (Apache-2.0) + `GraniteTokenizer` + `GraniteEmbedder` (CoreML, `.cpuAndNeuralEngine` pinned — GPU broken for compressed weights on macOS 26.5) + model resources (94 MB mlpackage + 24 MB tokenizer.json, uncommitted).
- `Packages/NotoSearch/Sources/NotoSearch/Semantic/`: `TextEmbedding` protocol (NotoSearch never imports NotoEmbedding — app injects), `SemanticChunker`, `SemanticIndexStore` (semantic.sqlite), `SemanticIndexer` (catalog-diff against search.sqlite notes table), `SemanticIndexCoordinator` (actor, single-flight + debounce), `SemanticSearcher` (Accelerate cblas_sgemv), `HybridSearchFusion` (RRF k=60).
- App: `SearchIndexController` triggers semantic refresh after FTS operations; `GraniteEmbedder` injected at startup; `NoteSearchSheet` two-stage search task (keyword paint → semantic fuse); Settings semantic stats + rebuild.

## Phase 4 — Chat `search` tool (added 2026-06-10)

Eugene's spec: a chat-agent tool that searches like the search sheet does (keyword FTS + semantic, RRF-fused, returning snippets and documents), with **created date and last-updated date filters**, so the model can answer e.g. "what did I talk about my projects in the last 5 days" by calling `search(query: "projects", updated_after: <today − 5d>)`.

Additional success criteria:
- SC10: The search index stores per-note `created_at` (frontmatter `created:`, filesystem creation-date fallback) and both keyword and semantic legs honor created/updated range filters. Existing index rows self-heal (re-index once) after the schema migration.
- SC11: `HybridNoteSearch` in NotoSearch is the single shared entry point: the search sheet's semantic stage and the chat tool run the same fusion code path.
- SC12: NotoChat advertises a `search` tool (only when the app injects a provider) with params query (required), created_after/created_before/updated_after/updated_before (ISO dates), limit; results feed citations (surfacedPaths) and the tool-trace UI (hits). grep stays for exact-string lookups; the system prompt steers the model accordingly.
- SC13: Live E2E — asking the chat "what did I talk about my projects in the last 5 days" triggers a `search` call with a computed date filter and produces a cited answer drawing on both keyword and semantic matches.

### Phase 4 implementation (2026-06-10)
- `created_at` indexed in `search.sqlite` (frontmatter `created:` > file creation date; pre-migration rows self-heal by re-indexing once); both FTS queries take a `SearchDateFilter` in SQL; `noteDates()` map filters the semantic leg.
- `HybridNoteSearch` (NotoSearch) = shared one-shot pipeline; the sheet's stage-2 keeps its two-paint UX via the same fusion internals.
- NotoChat: `ChatSearchProviding` protocol + `search` ToolDefinition (advertised only when the app injects a provider), date/limit arg parsing (limit clamped to 30), ranked output with per-hit path:line/kind/updated, surfacedPaths feed citations, hits feed the trace UI; system prompt steers search-vs-grep and date-cutoff computation.
- App: `HybridChatSearchProvider` (same `GraniteTextEmbedding` closure as the sheet) injected in `ChatSession`.
- Note: tool date filtering compares the index's dates (frontmatter created / file mtime); grep's filter reads frontmatter directly — near-identical in practice, documented divergence.

### Phase 4 verification (2026-06-10)
- SC10–SC12: 7 `HybridNoteSearchTests` + 6 `SearchToolTests` green; full affected-suite reruns green.
- SC13 (live): implementer run + independent audit (`.codex/evidence/20260610-171839-ios-visual-audit-chattool/`). Audit verdict PARTIAL with all functional criteria passing — date filter proven via a clean differential (unscoped query surfaces the backdated note at #1; "last 5 days" query reports nothing new); semantic reach through the tool proven (landlord question → 续租谈判 cited).
- Audit findings fixed same-day: (1) **steering** — flash-lite chose grep's date-listing over `search` ~75% of the time because grep's description advertised time-window listing; rewrote grep description (exact-match only, defer topical to search) + hardened the system-prompt routing rule → re-tested 3/3 fresh chats calling `search` with correct ISO cutoffs. (2) **trace legibility** — Search rows were anonymous; ChatSession/ChatSheet now render query + date filters + result count ("Searched 'projects' · updated ≥ 2026-06-05 · 12 results in 7 notes"); grep rows renamed "Matched" to distinguish.
- Discovered during E2E: `Config/LocalSecrets.xcconfig` is gitignored and must be copied into any new worktree (bundled OpenRouter key); note it also carries the Readwise token, so simulators with it auto-sync real Readwise captures into test vaults (the audit vault grew to 783 notes — handy scale test, surprising demo data).
- Known model-behavior note: saved transcripts in `Chats/` are indexed and can appear in subsequent searches (by design — chats are first-class notes).

## Stage 1 Image Search — describe-then-embed (added 2026-06-10)

Eugene's spec: embed images attached in documents — both remote URLs and vault uploads — so notes are findable by what's inside their images. Research (`.claude/brainstorm/multimodal-embedding-research.md`) ruled out unified/CLIP models (license/size/English-only); chosen architecture: image → Vision OCR + classification labels + alt text + note context → granite embedding as image-kind chunks in the existing index. Eugene is on iPhone 13 Pro (below the iOS 27 FM floor), so this Vision-based path is the primary, not a stopgap.

Additional success criteria:
- SC14: Markdown image references extracted accurately — `![alt](path)` vault attachments (percent-encoded paths decoded) and remote http(s) URLs, with line numbers; data: URIs and non-image links ignored.
- SC15: `VisionImageDescriber` produces OCR text (EN + ZH) and scene labels on-device; output carries a `describerVersion`.
- SC16: Image chunks index incrementally: invalidation key includes image bytes hash + describer version + embedding model version; unchanged images are never re-described or re-embedded; images removed from a note drop their chunks.
- SC17: Remote images download once into a local cache (keyed by URL hash) and index from cache; fetch failures skip gracefully (keyword/text search unaffected).
- SC18: E2E — a query matching only text *inside* an attached image surfaces the owning note in the search sheet (incl. cross-lingual via granite), with the image's line for navigation; chat `search` hits image chunks too.
- SC19: All existing suites stay green.

Design notes: `ImageDescribing` + `RemoteImageFetching` protocols live in NotoSearch with default implementations (Vision/ImageIO and URLSession are platform-neutral Apple frameworks) so the app needs no new wiring; `semantic_chunks` gains `kind`/`image_path`/`describer_version` columns (additive migration); image chunk IDs are stable per (note, image target); fusion surfaces image hits as section-kind results with an image-marked breadcrumb. Known v1 limitation: a remote image that fails to download is only retried when its note changes.

### Stage 1 verification (2026-06-10)
- SC14–SC17: 104 NotoSearch tests green, incl. 24 new (extractor, Vision describer with code-generated EN+ZH OCR images, cached fetcher with URLProtocol stubs, indexer incremental/removal/remote/alt-invalidation, fusion surfacing).
- SC18 live on iPhone 16 Pro sim (iOS 26.2): "rebuild semantic index" → Design Reference #1 via "in image: settings screen" with OCR snippet (note body contains none of those words); "solar energy dashboard output" → $120K Blueprint capture via a **remote pbs.twimg.com image** the pipeline fetched/cached/OCR'd live (11 remote tweet images indexed from the Readwise-synced vault, unstaged). iOS + macOS builds green.
- Residual/sim quirks: `VNClassifyImageRequest` fails on simulator ("espresso context") — describer degrades to OCR-only by design; labels expected to work on hardware, verify on-device. flowdeck `type` cannot input CJK, so the ZH-query-over-image-OCR UI probe is delegated to the audit (mechanism identical to the already-audited text cross-lingual path). **Independent audit: PASS on all 5 criteria** — incl. cross-lingual via pasteboard-injected 重建搜索索引 → Design Reference through English OCR, navigation, and bit-identical image-row stability across sweeps under live Readwise churn (181 rows). Evidence: `.codex/evidence/20260610-200935-ios-visual-audit-imagesearch/`. Auditor flag for future tuning: with a busy vault, a lone image hit can rank below many literal keyword matches (~#9 of 1,650-chunk vault) — correct RRF behavior, but an image-kind boost or weighted RRF is the lever if image hits should rank higher.

## Verification Status (2026-06-10)

- SC1–SC5: 35 NotoSearch semantic tests green (`swift test`).
- SC6–SC7: 10 NotoEmbedding tests green incl. 20 tokenizer golden cases + 8 embedding golden vectors (cos ≥ 0.999 vs Python).
- SC8: verified live on iPhone 16 Pro sim (iOS 26.2) and iPad mini sim — "rent negotiation with landlord" → 续租谈判 #1; "how to braise pork belly" → 红烧肉 #1; seeded vault embedded automatically (9 notes / 60 chunks); keyword leg unchanged. **Independent visual evidence audit: PASS on all 5 criteria** (incl. incremental indexing after an on-disk edit, proven with the auditor's own zero-overlap query). Evidence: `.codex/evidence/20260610-143423-ios-visual-audit/evidence.md`.
- SC9: full package sweep run (NotoVault/NotoSearch/NotoEmbedding/NotoChat/NotoReadwiseSync).
- macOS target builds; macOS panel shares `scheduleSearch`, so both legs run there too (visual pass on macOS not yet performed).

## Residual Risks

- Real-device ANE latency/memory unverified (simulator has no ANE) — physical-device check pending before any device install.
- Initial whole-vault embed on a real vault (~2k notes) takes minutes in the background at .utility priority; only Settings shows progress/stats.
- Embedding model stays resident (~150–250 MB) after first use; no idle unloading yet.
- macOS search panel not visually verified (build-only).
- Stale v1 `bge-small-en-v1_5.mlmodelc` ships in the app bundle (pre-existing, ~25 MB dead weight) — candidate for removal.

## Bugs

_None found during verification._
