# Semantic Search on Top of Keyword Search — Plan

**Date:** 2026-06-10
**Status:** Decisions resolved (see §5) — ready for implementation
**Research basis:** 7-agent workflow (code map of v2 NotoSearch / archive v1 stack / NotoChat+NotoVault infra / vision docs; web research on Apple embedding APIs, vector storage, hybrid ranking) + 2-agent follow-up on multilingual HF→CoreML models and Swift tokenization

---

## 1. What we're building

Add a semantic (embedding-based) leg to Noto's existing keyword search, fused into one ranked result list, fully on-device. Later, expose it to the AI chat agent as a `semantic_search` tool.

The v2 vision doc (`.claude/Noto v2/Brainstorm-new-direction.md`) already names hybrid keyword+semantic search as one of the five product pillars, with FTS5 + on-device embeddings as the stated architecture. This plan executes that pillar against the code that exists today.

---

## 2. What already exists (this is most of the work)

The current v2 codebase is much further along than "keyword search" suggests:

### NotoSearch package (`Packages/NotoSearch/`) — the substrate
- **SQLite FTS5** index with BM25 + custom boosts (title, section heading, folder, recency), porter tokenizer, prefix matching. Stored per-vault at `~/Library/Application Support/Noto/SearchIndexes/<vault-hash>/search.sqlite`.
- **`SearchSection` = ready-made chunks.** `MarkdownSearchDocumentExtractor` already splits every note into heading-bounded sections, each with `heading`, `level`, `lineStart/lineEnd`, `contentHash` (SHA256), and stripped `plainText`. The semantic index can ride these exact section rows — no new chunker needed, just a token-cap pass.
- **Incremental indexing lifecycle**: `SearchIndexCoordinator` (debounced 900ms refresh, single-flight full sweeps), crash-safe `PendingIndexQueue`, catalog diffing on size/mtime/content-hash, orphan deletion. The embedding pipeline plugs into this same dirty-detection flow.
- **Fallback path** when SQLite fails: brute vault scan. Semantic leg degrades gracefully to keyword-only the same way.

### NotoChat package — the tool surface
- Tools (`grep`/`read`/`list`) are static `ToolDefinition`s dispatched by name in `VaultTools.run()`. Adding `semantic_search` is: 1 definition + 1 method + 1 switch case.

### Archive (v1) — reference, mostly superseded
- **`archive/Packages/NotoEmbedding`**: CoreML `EmbeddingModel` wrapper pattern is a useful reference (model loading, MLModelConfiguration `.all` compute units, batch flow). Its `BertTokenizer`/`WordPieceTokenizer` do NOT apply to the multilingual candidates (granite = BPE, e5 = SentencePiece Unigram) — we vendor swift-transformers' Tokenizers module instead. The v1 model binary was never committed anyway.
- **`HybridRanker`** (alpha-weighted score normalization): superseded by research below — we'll use RRF instead.
- **`NotoHNSW`**: wraps third-party USearch → dead under the v2 no-dependency rule, and unnecessary (see §4).

---

## 3. Research conclusions (what shapes the design)

### Embedding source — multilingual requirement (Eugene's call) narrows the field

Eugene wants a **multilingual** model converted from HF to Core ML. Follow-up research (June 2026) on permissively-licensed multilingual models under ~150M params:

| | **granite-embedding-97m-multilingual-r2** (primary) | **multilingual-e5-small** (fallback) | NLContextualEmbedding (baseline) |
|---|---|---|---|
| License | Apache-2.0 | MIT | Apple built-in |
| MTEB Multilingual Retrieval (18 tasks) | **60.3** (IBM paper; ~2 pts behind 3×-larger EmbeddingGemma) | 50.9 | unbenchmarked; MLM, not retrieval-trained |
| Dims / max tokens | 384 / 32,768 | 384 / 512 | 512 iOS vs 768 macOS / ~256 |
| Languages | 52 enhanced incl. zh/ja/ko (200+ pretrained) | ~100 | 27, **but split into script-family models — English query can never match a Chinese note (incompatible vector spaces). Disqualifying for a mixed-language vault.** |
| Core ML size | ~97 MB int8 / ~49 MB 4-bit (computed, not yet measured) | **224 MB fp16 measured** / ~118 MB int8 | 0 (runtime asset download) |
| Query/passage prefixes | none | **required** (`query: ` / `passage: `) | n/a |
| Tokenizer | BPE 180k vocab (easiest Swift path) | XLM-R SentencePiece Unigram 250k | internal (zero work) |
| Conversion evidence | architecture proven (ModernBERT-CoreML repo incl. 4-bit + convert.py), **this checkpoint not yet converted by anyone** | **2 public .mlpackage repos; measured 15 ms ANE on iPhone 15 Pro** | n/a |

Rejected: **paraphrase-multilingual-MiniLM** (STS-trained not retrieval, 128-token cap, same size as e5), **EmbeddingGemma-300m** (best quality at 62.5 but Gemma ToU: gated repo, ToS flow-down obligations, Google remote-restriction/termination rights inside a shipped app), **jina-v5-nano** (CC-BY-NC), **Qwen3-0.6B** (~300 MB int4, over budget), **bge-small-en** (English-only — fails the multilingual requirement), **Foundation Models** (no embedding vectors on iOS 26), **CSUserQuery semantic mode** (no scores, documented silent failures through iOS 26 betas), **NLEmbedding** (superseded), **remote APIs** (breaks offline-first; vault leaves device).

### Tokenization in Swift — solved problem
Vendor the `Sources/Tokenizers` module from **huggingface/swift-transformers** (Apache-2.0, 12 files ~150 KB): it is the only pure-Swift SentencePiece-Unigram implementation in existence and is **unit-tested against multilingual-e5-small exactly** (expected-ids test in their suite); it also covers BPE for granite. Vendoring = copy module + small `Config` JSON shim + delete Jinja/chat-template paths (~1–2 days). Known fidelity gap: `precompiled_charsmap` normalization is approximated (same as transformers.js) — affects only exotic inputs (e.g., halfwidth katakana), negligible for mean-pooled similarity. Reference glue for XLM-R models: jkrukowski/swift-embeddings.

### Vector search — brute force, no index structure
Measured (M3 Max, `cblas_sgemv`, top-k included): **0.2 ms @ 10k×512-dim, 2.4 ms @ 100k×512**. iPhone extrapolation ~2–4× slower — every realistic Noto vault clears an interactive budget by 10×. HNSW buys nothing below ~500k vectors and brings delete/persistence pathology (the worst fit for a notes app with constant edits). v1 only had HNSW because it indexed per-paragraph; we won't rebuild it.

→ Store vectors as BLOBs in the existing `search.sqlite` (libsqlite3 is Apple-shipped; blobs ≤4 KB are faster in SQLite than as files), load into one contiguous fp32 matrix lazily, score with a single `cblas_sgemv` call.

### Fusion — RRF, not score normalization
BM25 scores and cosine similarities are incompatible distributions; min-max normalization (v1's approach) is per-query brittle. **Reciprocal Rank Fusion** (`Σ 1/(60+rank)`) is score-agnostic, zero-tuning, and the industry default (Elasticsearch, Azure). Tuned weighted fusion only wins with labeled relevance data — which a personal notes app never has.

### Chunking — sections + contextual headers
- Notes ≤ ~300 tokens → embed whole note as one chunk (most daily notes).
- Larger notes → one chunk per existing `SearchSection`, force-split >~400 tokens.
- **Prepend `NoteTitle > Heading path` to each chunk's text before embedding** (not displayed). Published result: cuts top-20 retrieval failures ~49%. This is the model-agnostic substitute for `query:`/`passage:` prefixes (which do NOT apply to NLContextualEmbedding, and DO apply if we ever swap to an E5-family model).

### Query UX — two-lane
- Keyword/FTS leg: synchronous on every keystroke (already is).
- Semantic leg: debounced ~250 ms, gated at ≥3 chars / 1 word, embed query (~20–30 ms), cosine scan (<5 ms), collapse chunk hits → note level (max-chunk-score), RRF-fuse with the keyword list, dedupe by note UUID.
- Merge without yanking rows the user is about to tap (stable merge below the fold or re-rank on next keystroke).

---

## 4. Proposed architecture

```
Packages/
  NotoEmbedding/                  # NEW package
    Tokenizers/                   # vendored from huggingface/swift-transformers (Apache-2.0):
                                  #   Unigram (e5) + BPE (granite) + golden-vector parity tests
    EmbeddingModel                # CoreML wrapper; Bundle.module resources; injectable model URL;
                                  #   mean-pool + L2-normalize; optional query/passage prefixing
    Resources/ <model>.mlpackage + tokenizer.json   (granite-97m-r2 or multilingual-e5-small)

  NotoSearch/                     # EXTENDED
    SemanticIndexStore            # NEW: chunks table in search.sqlite
                                  #   (chunk_id, note_id, section_hash, model_version,
                                  #    dims, embedding BLOB, heading_path, line_start/end)
    SemanticSearcher              # NEW: lazy in-memory fp32 matrix + cblas_sgemv top-k
    HybridFusion                  # NEW: RRF(k=60), chunk→note collapse, UUID dedupe
    SearchIndexCoordinator        # touched: after FTS upsert, enqueue changed sections
                                  #   for embedding (same debounce, same pending queue)
    MarkdownSearchDocumentExtractor  # touched: token-cap pass over sections

Noto/ (app target)
  NoteSearchSheet                 # touched: two-lane results, semantic debounce
  SettingsView                    # touched: "Rebuild semantic index" + progress

Packages/NotoChat/                # Phase 4
  VaultTools                      # + semantic_search ToolDefinition & dispatch
```

**Invalidation** (all four layers, mirrors what NotoSearch already does):
1. Per-chunk `section_hash` — re-embed only changed sections; idempotent, crash-resumable.
2. Note mtime/size as the cheap pre-filter (existing catalog diff).
3. Hard `DELETE` rows on note deletion (no tombstones — brute force has no graph to repair).
4. `model_version` column — model swap ⇒ automatic full re-embed; vault is source of truth so worst case is always "rebuild," never "corrupt."

**Scale envelope:** 2k notes ≈ 5k chunks ≈ 7 MB of vectors, ~2–3 min one-time background embed on iPhone, <1 ms per query scan. 20k notes ≈ 50k chunks ≈ 73 MB fp32 (→ fp16 if ever needed), ~5 ms scan on iPhone.

---

## 5. Decisions (resolved 2026-06-10 with Eugene)

1. **Embedding model: ✅ RESOLVED BY SPIKE (2026-06-10) — granite-embedding-97m-multilingual-r2, int8, pinned to CPU+ANE.** Conversion succeeded first approach; int8 retrieval is identical to fp32 reference (hit@1 0.89 / hit@5 1.00 / cross-lingual hit@1 0.67 on zh/en/ja fixtures) while e5-small scored 0.00 cross-lingual hit@1 with rank-12–14 failures. 94 MB model + 24 MB tokenizer, 13.4 ms @ seq 512 on M3 Max ANE. Full results: `.claude/spikes/embedding-conversion-spike-20260610.md`; pipeline: `scripts/embedding-spike/`. `model_version` column still makes any later swap a clean re-embed.
2. **Result presentation: single blended list.** RRF-fused; keyword hits paint instantly, semantic merges in stably after ~250 ms debounce.
3. **Scope: search UI + chat tool**, phased — `semantic_search` tool lands as Phase 4.

---

## 6. Phases (each gated on tests per CLAUDE.md)

**Phase 0 — Model conversion spike. ✅ DONE 2026-06-10.** granite-97m-r2 converted (torch.jit.trace + eager attention; two interventions: `reference_compile=False`, additive-mask fill −1e4 for fp16/ANE safety). int8 = 94 MB, parity min-cosine 0.9997, retrieval identical to fp32, 13.4 ms @ seq 512 ANE. e5 fallback evaluated and rejected (cross-lingual failures). iOS-runtime validated on an iPhone 16 Pro simulator (iOS 26.2): min cosine 0.99974 vs PyTorch ref, 0.99999 vs Mac CoreML run — physical-device ANE check folded into Phase 2. Results: `.claude/spikes/embedding-conversion-spike-20260610.md`. Carry-forwards: pin `.cpuAndNeuralEngine` (GPU path broken for compressed weights on macOS 26.5), CLS pooling baked into graph, BPE tokenizer path, fixed 1×512 input (enumerated 256/512 shapes = later latency optimization).

**Phase 1 — NotoEmbedding package. ✅ DONE 2026-06-10** (vendored swift-transformers BPE tokenizer @1.3.3 + 2 upstream fixes; 20 golden token cases + 8 golden vector cases green).
Original scope:  Vendor swift-transformers `Tokenizers` module (Apache-2.0 attribution; + small Config JSON shim, strip Jinja/Hub) and port their multilingual-e5 expected-ids test as the regression gate. `EmbeddingModel` on `Bundle.module` with mean-pool + L2-normalize; prefix handling (`query:`/`passage:`) behind the model config so e5 and granite are interchangeable. `swift test` clean.

**Phase 2 — Semantic index in NotoSearch. ✅ DONE 2026-06-10** (semantic.sqlite separate from search.sqlite; catalog-diff incremental indexer; vDSP brute-force searcher; RRF fusion; 35 tests green).
Original scope:  `SemanticIndexStore` (schema above), embedding step wired into `SearchIndexCoordinator`'s existing refresh/pending-queue flow, chunk token-cap + contextual-header builder, `SemanticSearcher` (Accelerate scan). Unit tests: incremental re-embed on section edit, deletion, model-version bump, empty/tiny notes (3-word minimum), boundary cases.

**Phase 3 — Hybrid query + UI. ✅ DONE 2026-06-10** (two-stage scheduleSearch; SemanticIndexCoordinator wired into SearchIndexController; Settings rebuild+stats; verified cross-lingual E2E on iPhone+iPad sims).
Original scope:  RRF fusion + chunk→note collapse + dedupe (pure logic, package-tested). NoteSearchSheet two-lane wiring, debounce, settings rebuild button with progress. Simulator verification on iPhone + iPad mini, plus macOS.

**Phase 4 — Chat tool.** `semantic_search(query, limit)` in VaultTools returning chunk snippets + paths (feeds citations naturally). Package tests + one live E2E.

---

## 7. Risks
- **First-to-convert granite-97m-r2:** nobody has published a Core ML conversion of this checkpoint (released 2026-04-29). Bounded by the ModernBERT-CoreML template + the e5 fallback with zero conversion risk. Phase 0 exit criteria make this a one-day decision, not a project risk.
- **Quantization quality:** int8 is typically ~1% retrieval loss; 4-bit PTQ on non-QAT models is risky → validate each compression step against the fp32 reference eval before accepting it.
- **Tokenizer parity:** a silent tokenization divergence degrades every vector → golden expected-ids tests (ported from swift-transformers) + golden-vector tests in Phase 0/1, non-negotiable. Known charsmap approximation affects only exotic normalization edge cases.
- **App size:** +~50–120 MB depending on quantization outcome. Flag: if this is unacceptable, the alternative is runtime model download (own CDN) — added complexity, deferred unless needed.
- **Initial index time on large vaults:** background task + progress UI; embed newest-modified notes first so recent notes are searchable immediately.
- **Short-query noise:** mean-pooled embeddings are weak on 1–2 word queries → ≥3-char gate + RRF (keyword leg dominates exact lookups anyway).
- **iCloud undownloaded files:** reuse NotoSearch's existing skip-and-retry-on-next-refresh pattern.
- **Memory on iPhone:** trivial at realistic scale (vectors: 5k chunks × 384d × 4B ≈ 7 MB); fp16 matrix is the lever if a vault ever passes ~50k chunks. Model RAM: ~100–200 MB during embedding — load/unload around indexing bursts.

## 8. Explicitly not doing
- HNSW / ANN index (unjustified below ~500k vectors; delete pathology).
- Score normalization fusion (v1's HybridRanker approach — brittle).
- CSUserQuery semantic mode, Foundation Models embeddings (unavailable/unreliable).
- Syncing vectors across devices (index is per-device derived data, like FTS today).
