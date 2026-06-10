# Bug 019: Multi-concept cross-lingual query misses a relevant note ("vibe code remote control")

## Status: FIX DEPLOYED

## Description

Searching `vibe code remote control` on Eugene's real vault (~895 notes, ~10k+ chunks) does not surface `Captures/国内终于有厂商要出了.md`, which (a) literally contains "vibe coding" and (b) attaches 4 remote product images of a remote-control-looking device. Expected: the note appears in the blended results.

## Facts established

- Note is in FTS (`note_id 5D5CEDD3…`) and in the semantic index: 1 text chunk + 4 image chunks, all with good Chinese OCR (`MagSafe磁吸`, `麦克风`, `键轴设计`…).
- Note text contains "你的 vibe coding 好搭子" — matches `vibe* code*` in FTS, but the full query becomes `vibe* code* remote* control*` (implicit AND); "remote"/"control" appear nowhere in the note text → keyword leg cannot match.
- Image OCR text lives only in the semantic index (by design), so FTS gets no help from the images.
- Whether VNClassify labels (the only "remote control" visual signal, in English) were included in the image chunks' embedded text is unverified — embedded text isn't persisted, only snippets (which show OCR).

## Steps to Reproduce

1. Mac app on Eugene's real vault, indexes fully built.
2. Open search, type `vibe code remote control` (Title + body).
3. Observe results: 国内终于有厂商要出了 absent.

## Root Cause

Three stacked causes, established empirically against the real index (harness: /tmp/noto-debug-search):

1. **Keyword AND semantics**: `vibe code remote control` → FTS `vibe* code* remote* control*` (all terms required); the note matches only vibe+code → invisible to the keyword leg.
2. **Semantic dilution**: best chunk ranked #361 (0.796) — dozens of pure English vibe-coding captures score 0.84+ and wall off the top-50. Forced-label probe: even WITH a literal "remote control" label the image chunk would rank ~#131. The "looks like a remote control" concept is visual-only; VNClassify's actual output for these product renders maxes at 0.20 confidence ("machine/thermometer/keypad") with no remote_control candidate — Vision taxonomy limit, not a code bug. This concept is unreachable without a visual-semantic leg (Stage 3 / FG-CLIP2 — this bug is that trigger case).
3. **Fusion slot starvation**: after adding an OR fallback the note entered the keyword leg (result #55, note-rank 36/191) but fused output emitted ALL section rows per note (one note ate 4 of the top 8 slots), pushing note-rank-36 out of the 60-row list.

## Fix

1. `MarkdownSearchEngine.orFTSQuery` + recall fallback in `SearchIndexStore.search`: when the strict AND pass returns fewer than `limit` rows (titleAndContent scope, unquoted multi-token queries), rerun OR-joined and append deduped — BM25 keeps full matches on top; quoted queries stay strict; date filters apply to both passes.
2. `HybridSearchFusion.fuse`: cap emission at 2 rows per note so distinct notes fill the list.
3. Deeper candidates: keyword 60→150 rows, fused list 60→100 (sheet + HybridNoteSearch defaults).

## Success Criteria

### 1. Partial-term notes surface for multi-concept queries
- [x] Verified in unit test
- [x] Verified against real vault index
**Unit test:** `NEW` — `KeywordORFallbackTests` (5 cases: partial matches surface, full matches rank first, quoted stays strict, single-term unchanged, date filter applies)
**Real-data verification:** harness on copies of the real indexes — `vibe code remote control` → target at fused rank 67 (was ABSENT); `vibe coding remote` → 55; `vibe code 麦克风` → 17.

### 2. Fused list no longer starved by multi-section notes
- [x] Verified in unit test
**Unit test:** `NEW` — `HybridSearchFusionTests.testPerNoteRowCapPreventsSlotStarvation`

### 3. No regressions
- [x] 110 NotoSearch + 45 NotoChat tests green (title-only scope precision preserved — caught and fixed during development).

### 4. Known limitation (documented, not fixed here)
Ranking the note HIGH for "remote control" requires visual-semantic understanding (CLIP-style image leg or VLM captions) — Stage 3 in the plan doc. Vision labels cannot express it (verified: no remote_control candidate, max 0.20 confidence).

## Investigation Log

### Attempt 1 — live scoring reproduction

**Hypothesis:** H1/H2. **Method:** host-side harness (NotoEmbedding + NotoSearch against a read-only copy of the Mac's real semantic.sqlite): embed the exact query, run SemanticSearcher, locate the note's 5 chunks in the ranking; reconstruct candidate embedded texts to infer label presence.


### Attempt 1 — result

OR fallback alone moved the note into the keyword leg (#55) but fusion emission starved it out. Adding the per-note row cap + deeper limits landed it at fused rank 67 with production defaults. FIXED pending device verification by Eugene.
