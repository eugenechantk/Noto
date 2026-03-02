# PRD: Hybrid Search API + Search UI

## Overview

The orchestration layer that ties keyword search (FTS5) and semantic search (embeddings + HNSW) into a single unified search experience. Includes the hybrid ranking algorithm, natural language date filter extraction, and the search UI.

**Scope:** Search service API, hybrid ranking, date filter parsing, search result UI.

**Dependencies:**
- PRD-keyword-search (FTS5Engine)
- PRD-semantic-search (SemanticEngine)
- PRD-search-foundation (DirtyTracker, FTS5Database, DateRange)
- Figma design: figma.com/design/9nh3TpDEoZx8Pt8hVUrJgV, node 24:767

**Phase:** Must start after keyword search and semantic search engines are functional. However, pure-logic components (`DateFilterParser`, `HybridRanker`, `BreadcrumbBuilder`) have no cross-PRD dependencies and can be built in parallel with Phase 1 of any PRD.

---

## Core Requirements

| Requirement | Implication |
|-------------|-------------|
| One search box, no mode switching | Single input drives both keyword + semantic |
| Results ranked by combined relevance | Hybrid scoring algorithm |
| Natural language date filtering | Rule-based temporal phrase parsing |
| Search-on-submit (not search-as-you-type) | One embedding generated per query |
| Threshold-based results, not fixed top-K | Only return results above relevance threshold |
| Breadcrumb path on each result | Walk ancestor chain for display |
| Bottom sheet UI | Sheet overlays current note |
| "Ask AI" action row | Shares same query input, separate from search results |

---

## Hybrid Search API

### SearchQuery

Both the rule-based and AI paths produce the same structured query:

```
SearchQuery {
    text: String              // search terms (temporal phrases stripped)
    dateRange: DateRange?     // optional date filter (from foundation)
}
```

### SearchResult

```
SearchResult {
    blockId: UUID
    content: String           // block text (for display)
    breadcrumb: [String]      // ancestor path, e.g. ["Home", "Not too bad"]
    hybridScore: Double       // combined normalized score, [0, 1]
}
```

### SearchService Interface

```
SearchService.search(query: SearchQuery) -> [SearchResult]
```

---

## Date Filter Extraction

### Rule-Based Path (Regular Search)

Parse temporal phrases from the query before searching. Use `NSDataDetector` with `.date` type + a small regex layer for common patterns.

**Recognized patterns:**
- "today" → `createdAt >= startOfDay`
- "yesterday" → yesterday's date range
- "last week" / "this week" → 7-day window
- "in March" / "in 2024" → month/year range
- "recent" → last 7 days

**Process:**
1. Scan query string for temporal phrases
2. If found: extract date range, strip the temporal phrase from the query text
3. Pass cleaned text + date range as `SearchQuery`

If no temporal phrase is detected, `dateRange` is nil (global search).

### Ask AI Path

The LLM decomposes the query into intent + structured filters, producing the same `SearchQuery`. This path handles complex cases like "things about food from January" → text: "food", dateRange: January.

The AI path is out of scope for this PRD's implementation but the `SearchQuery` interface supports it.

---

## Hybrid Ranking Algorithm

### Pipeline

1. **Filter extraction** — parse date filter from query
2. **Parallel search** — run FTS5 and HNSW simultaneously with the same date filter
3. **Union** — merge candidate sets from both engines
4. **Score & rank** — compute hybrid scores, threshold, sort

### Parallel Search Execution

**FTS5:** Query with date filter via post-filter. Returns all results above BM25 threshold.

**HNSW:** Over-fetch top 200 from `usearch`, post-filter by date range, apply cosine similarity threshold (>= 0.3).

### Score Normalization

Both raw scores must be normalized to [0, 1] before combining.

**BM25 (keyword):**
- FTS5 returns negative scores (more negative = better match)
- Normalize over the result set: `normalized = (score - minScore) / (maxScore - minScore)`
- Single result: score = 1.0

**Cosine similarity (semantic):**
- Already in [0, 1] practically (positive embeddings)
- Normalize over the result set: `normalized = (sim - minSim) / (maxSim - minSim)`
- Single result: score = 1.0

### Score Combination

```
hybridScore = α * keywordScore + (1 - α) * semanticScore
```

Start with `α = 0.6` (keyword-heavy):
- Users typing exact words expect exact matches first
- Semantic is the "you might also mean" tier
- Tune empirically later

### Missing Scores (Disjoint Result Sets)

When a result only appears in one engine's output:
- Keyword-only result: semanticScore = 0 → max possible hybrid = 0.6
- Semantic-only result: keywordScore = 0 → max possible hybrid = 0.4
- Both engines match: strongest signal, ranks highest

This naturally rewards results found by both engines.

### Short-Circuit Optimizations

- **Exact match boost:** If query appears verbatim in a block, boost significantly
- **Empty keyword results:** FTS5 returns nothing → fall back to pure semantic ranking (α = 0)
- **Single common word:** Keyword search alone is probably sufficient
- **Long natural-language query:** Full sentence with no exact matches → lean heavier on semantic

---

## Search UI

### Design (from Figma)

The search view is a **bottom sheet** that slides up over the current note.

**Layout (top to bottom):**
1. Grabber handle
2. Sheet title bar with close button
3. "Ask AI" action row — shows the query with an AI icon, tappable to send to AI chat
4. "Results" section header
5. Search result rows (scrollable list)
6. Search bar at the **bottom** (liquid glass style) — text input + clear button + submit button

### Search Result Row

Each row displays:
- **Title line**: Block content text (17pt, primary label color)
  - Single-line blocks: truncated with ellipsis
  - Longer blocks: wraps to multiple lines
- **Breadcrumb line**: Ancestor path in secondary gray (15pt)
  - Format: "Home / Note Title / Parent Block"
  - Constructed by walking the block's ancestor chain

Rows are separated by standard iOS separators.

### Breadcrumb Construction

For each search result, walk the block's parent chain up to root:
1. Collect ancestor block titles (content, first line or first N characters)
2. Reverse to get root-first order
3. Join with " / " separator
4. The top-level ancestor is always "Home" (or the root note name)

### Interaction

- **Submit button:** Triggers search — extracts date filter, runs FTS5 + HNSW, ranks results, displays
- **Tap result row:** Dismiss sheet, navigate to the matched block in its note tree
- **"Ask AI" row:** Sends the same query to the AI chat path (separate feature)
- **Clear button:** Clears the search text

### Search Flow

1. User types query in search bar
2. User taps submit button
3. Date filter extracted from query (rule-based)
4. FTS5 and HNSW search run in parallel
5. Results merged, scored, thresholded, sorted
6. Result rows displayed with content + breadcrumb
7. User taps a result → navigate to that block

---

## Dirty Flush on Search Open

When the search sheet appears, before the user can submit a query, trigger the dirty flush pipeline:
1. Persist in-memory dirty set to `dirty_blocks` table (via `DirtyTracker` from foundation)
2. Flush `dirty_blocks` to FTS5 (via `FTS5Indexer` from keyword search)
3. Generate embeddings + insert into HNSW for dirty blocks (via `EmbeddingIndexer` from semantic search)

This ensures the index is fresh when the user searches. For small dirty sets (typical case), this completes in under 100ms and is imperceptible. For large dirty sets (e.g., first search after writing 500 blocks), show a brief loading indicator.

---

## Performance Targets

| Operation | Target |
|-----------|--------|
| Date filter extraction | < 1ms |
| FTS5 query | < 10ms |
| HNSW query | < 10ms |
| Query embedding generation | < 30ms |
| Score normalization + ranking | < 5ms |
| **Total search latency** | **< 60ms** (after dirty flush) |
| Breadcrumb construction per result | < 1ms |

---

## Components

| Component | Responsibility |
|-----------|---------------|
| `DateFilterParser` | Extracts date ranges from natural language query strings. Returns cleaned query text + optional `DateRange`. **No cross-PRD dependencies — can be built in parallel.** |
| `HybridRanker` | Score normalization and combination logic. Takes raw FTS5 + HNSW results, normalizes to [0, 1], applies weighted combination, thresholds, sorts. **No cross-PRD dependencies — can be built in parallel.** |
| `BreadcrumbBuilder` | Walks a block's ancestor chain and produces the display string. **Depends only on Block model (existing).** |
| `SearchService` | Orchestrates the full search pipeline. Takes raw query string, parses date filter, runs FTS5 + HNSW in parallel, normalizes scores, combines with hybrid ranking, constructs breadcrumbs, returns `[SearchResult]`. **Depends on FTS5Engine + SemanticEngine.** |
| `SearchSheet` | SwiftUI view — bottom sheet with search bar, "Ask AI" row, results list. **Depends on SearchService.** |
| `SearchResultRow` | SwiftUI view — single result row with title + breadcrumb. |

---

## Testing Strategy

### Unit Tests

Pure logic components — no blocks, no engines needed.

| Area | What to test |
|------|-------------|
| **Date filter parsing** | "today", "yesterday", "last week", "this week", "last month", "in March 2024", "recent", "last N days" — correct date range + stripped query |
| **No false positives** | "march to the beat" does not extract a date; bare month names without "in"/"last" not matched |
| **Multiple temporal phrases** | First (leftmost) match wins |
| **Empty text after strip** | Query "today" → empty text + date range (triggers date-only path) |
| **BM25 normalization** | Negative scores normalized to [0, 1]; single result → 1.0 |
| **Cosine normalization** | Cosine similarities normalized to [0, 1]; single result → 1.0 |
| **Hybrid scoring** | Both-engine results rank highest; keyword-only caps at α; semantic-only caps at (1-α) |
| **Alpha short-circuit** | Empty keyword → α=0; empty semantic → α=1 |
| **Exact match boost** | Verbatim query in content gets 1.5x keyword boost, capped at 1.0 |
| **Breadcrumb format** | Root → "Home"; nested → "Home / Parent / Child"; long titles truncated at 30 chars |

### Integration Tests

Full pipeline tests with ~15-20 blocks at various depths and dates (SearchTestFixture).

| Area | What to test |
|------|-------------|
| **End-to-end keyword** | Create blocks → flush → keyword search → correct block returned |
| **End-to-end semantic** | Create blocks → flush → semantic search → conceptually similar block found |
| **Hybrid ranking** | Block matching both engines ranks above single-engine match |
| **Date filter + search** | "work yesterday" → only yesterday's blocks |
| **Date-only query** | "today" → all today's blocks sorted by recency |
| **Dirty flush on search** | Edit → open search → `ensureIndexFresh()` → updated content found |
| **Breadcrumb accuracy** | Deeply nested block → breadcrumb matches ancestor chain |
| **Result navigation** | Tap result → navigation path built → navigates to block |

### UI Tests (XCUITest)

Launch with `-UITesting` + `SEARCH_TEST_SEED=1` to pre-populate fixture blocks.

| Area | What to test |
|------|-------------|
| **Sheet presents** | Tap search bar → bottom sheet appears |
| **Search flow** | Type query → submit → result rows appear |
| **Result navigation** | Tap result → sheet dismisses → block visible |
| **Clear button** | Type → clear → text and results cleared |
| **Ask AI row** | Type query → row shows query text |
| **Empty results** | Gibberish query → no results |
| **Date filter** | "work yesterday" → only yesterday's block |
