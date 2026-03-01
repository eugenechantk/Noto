# Spec: Hybrid Search API + Search UI

Based on [PRD-hybrid-search-and-ui.md](./PRD-hybrid-search-and-ui.md).

---

## User Stories

1. **As a user**, I type a query in one search box and see results ranked by combined keyword + semantic relevance.
2. **As a user**, I can type "what did I write today" and see only blocks created today, with the temporal phrase automatically parsed.
3. **As a user**, I see a breadcrumb path on each result (e.g., "Home / Design Notes / Color Theory") so I know where the block lives.
4. **As a user**, I tap a result and navigate directly to that block in its note tree.
5. **As a user**, I see an "Ask AI" option that takes my same query to AI chat.
6. **As a user**, I only see relevant results — no padding with low-relevance matches.
7. **As a user**, the search index is silently brought up to date when I open search, so results reflect my latest edits.

---

## Acceptance Criteria

- [ ] Single search input triggers both FTS5 keyword and HNSW semantic search in parallel
- [ ] Results are ranked by hybrid score (α=0.6 keyword, 0.4 semantic)
- [ ] Results that appear in both engines rank higher than single-engine matches
- [ ] Keyword-only results (semantic score 0) and semantic-only results (keyword score 0) are both included
- [ ] Temporal phrases ("today", "last week", "in March") are extracted and applied as date filters
- [ ] Temporal phrases are stripped from the query before search execution
- [ ] If no temporal phrase is detected, search is global (no date filter)
- [ ] Each result row shows block content + breadcrumb path
- [ ] Breadcrumb correctly walks the ancestor chain to root
- [ ] Tapping a result dismisses the sheet and navigates to the block
- [ ] "Ask AI" row is present and tappable (navigation to AI chat is out of scope)
- [ ] Search bar is at the bottom of the sheet (liquid glass style)
- [ ] Dirty flush runs on search sheet appear, ensuring fresh results
- [ ] For large dirty sets, a loading indicator is shown during flush
- [ ] Total search latency < 60ms after dirty flush completes
- [ ] Empty keyword results → pure semantic ranking (α falls back to 0)
- [ ] Exact verbatim match gets a score boost

---

## Technical Design

### Architecture Overview

```
SearchSheet (SwiftUI)
    │
    │ raw query string
    ▼
┌────────────────────┐
│ SearchService      │
│                    │
│ 1. Flush dirty     │ → DirtyTracker + FTS5Indexer + EmbeddingIndexer
│ 2. Parse date      │ → DateFilterParser
│ 3. Parallel search │ → FTS5Engine + SemanticEngine (async let)
│ 4. Hybrid rank     │ → HybridRanker
│ 5. Build results   │ → BreadcrumbBuilder
│                    │
└────────────────────┘
    │
    │ [SearchResult]
    ▼
SearchSheet displays results
    │
    │ user taps result
    ▼
ContentView.navigationPath updated → navigates to block
```

### Data Types

```swift
struct SearchQuery {
    let text: String          // search terms (temporal phrases stripped)
    let dateRange: DateRange? // optional date filter
}

struct DateRange {
    let start: Date
    let end: Date
}

struct SearchResult: Identifiable {
    let id: UUID              // block ID
    let content: String       // block text (for display)
    let breadcrumb: String    // formatted ancestor path, e.g. "Home / Design Notes"
    let hybridScore: Double   // combined score [0, 1]
}
```

### Component Details

#### 1. `DateFilterParser`

Location: `Noto/Search/DateFilterParser.swift`

Extracts temporal phrases from a raw query string and returns a cleaned query + optional date range.

```swift
struct DateFilterParser {
    func parse(_ rawQuery: String) -> SearchQuery
}
```

**Algorithm:**

1. Define regex patterns for common temporal phrases:
   ```
   "today"                    → (Calendar.current.startOfDay(for: .now), endOfDay)
   "yesterday"                → (startOfYesterday, endOfYesterday)
   "last week"                → (7 days ago start, now)
   "this week"                → (start of current week, now)
   "last month"               → (start of last month, end of last month)
   "this month"               → (start of current month, now)
   "last (\d+) days"          → (N days ago, now)
   "recent" / "recently"      → (7 days ago, now)
   ```

2. For month/year patterns ("in March", "in 2024", "in March 2024"):
   Use `NSDataDetector` with `.date` checking type to extract date references, then compute the full month/year range.

3. Scan the raw query against all patterns (case-insensitive).

4. If a match is found:
   - Compute the `DateRange`
   - Remove the matched substring from the query
   - Trim whitespace from the remaining text
   - Return `SearchQuery(text: cleanedText, dateRange: range)`

5. If no match: return `SearchQuery(text: rawQuery, dateRange: nil)`

**Edge cases:**
- Multiple temporal phrases: use the first match (leftmost)
- Empty text after stripping: return empty text (will produce no FTS5 results, semantic may still work)
- Ambiguous phrases like "march" (could be month or verb): regex patterns are anchored to common phrasing ("in March", "last March") — bare "march" is not matched

#### 2. `SearchService`

Location: `Noto/Search/SearchService.swift`

Orchestrates the full search pipeline. This is the single entry point for search.

```swift
class SearchService {
    let dirtyTracker: DirtyTracker
    let fts5Indexer: FTS5Indexer
    let embeddingIndexer: EmbeddingIndexer
    let fts5Engine: FTS5Engine
    let semanticEngine: SemanticEngine
    let dateFilterParser: DateFilterParser
    let hybridRanker: HybridRanker
    let modelContext: ModelContext

    // Full search pipeline
    func search(rawQuery: String) async -> [SearchResult]

    // Flush dirty blocks (called on search sheet appear)
    func ensureIndexFresh() async
}
```

**`ensureIndexFresh()` algorithm:**
1. `await dirtyTracker.flush()` — persist in-memory dirty set
2. Fetch all dirty blocks from `dirty_blocks` table
3. Run FTS5 and embedding indexing for dirty blocks (sequential — both need the same dirty set)
4. Save HNSW index

**`search()` algorithm:**
1. Parse date filter: `dateFilterParser.parse(rawQuery)` → `SearchQuery`
2. If `query.text` is empty and `query.dateRange` is nil, return `[]`
3. Run keyword and semantic search in parallel:
   ```swift
   async let keywordResults = fts5Engine.search(
       query: query.text, dateRange: query.dateRange, modelContext: modelContext
   )
   async let semanticResults = semanticEngine.search(
       query: query.text, dateRange: query.dateRange, modelContext: modelContext
   )
   ```
4. Pass both result sets to `hybridRanker.rank(keyword:, semantic:)`
5. For each ranked result, build breadcrumb + fetch content:
   - Fetch `Block` from SwiftData by ID
   - Get `block.content` for display
   - Call `BreadcrumbBuilder.build(for: block)` for the breadcrumb string
6. Return `[SearchResult]` sorted by `hybridScore` descending

**Short-circuit: empty query text with date range:**
If `query.text` is empty but `dateRange` is set (e.g., user typed just "today"), skip FTS5 and semantic search. Instead, fetch all blocks in the date range from SwiftData and return them sorted by `updatedAt` descending. This handles the "show me what I wrote today" case.

#### 3. `HybridRanker`

Location: `Noto/Search/HybridRanker.swift`

Score normalization, combination, and thresholding.

```swift
struct HybridRanker {
    let alpha: Double = 0.6  // keyword weight

    func rank(
        keyword: [KeywordSearchResult],
        semantic: [SemanticSearchResult]
    ) -> [RankedResult]
}

struct RankedResult {
    let blockId: UUID
    let hybridScore: Double
}
```

**Algorithm:**

1. **Build lookup maps:**
   ```swift
   let keywordMap: [UUID: Double] = // blockId → raw BM25 score
   let semanticMap: [UUID: Float] = // blockId → raw cosine similarity
   ```

2. **Union all block IDs** from both maps.

3. **Normalize keyword scores** (BM25):
   - FTS5 returns negative scores (more negative = better)
   - If only one result: normalized = 1.0
   - Otherwise: `normalized = (score - worstScore) / (bestScore - worstScore)`
   - Where `bestScore` = most negative (min), `worstScore` = least negative (max)
   - Results not in keyword set get normalized score = 0.0

4. **Normalize semantic scores** (cosine similarity):
   - If only one result: normalized = 1.0
   - Otherwise: `normalized = (sim - minSim) / (maxSim - minSim)`
   - Results not in semantic set get normalized score = 0.0

5. **Short-circuit check:**
   - If keyword results are empty: set `effectiveAlpha = 0.0` (pure semantic)
   - If semantic results are empty: set `effectiveAlpha = 1.0` (pure keyword)
   - Otherwise: `effectiveAlpha = alpha` (0.6)

6. **Exact match boost:**
   - For each keyword result, check if the query text appears verbatim in the block content (case-insensitive)
   - If yes: multiply that result's normalized keyword score by 1.5 (capped at 1.0 after combination)

7. **Compute hybrid scores:**
   ```swift
   for blockId in allBlockIds {
       let kw = normalizedKeyword[blockId] ?? 0.0
       let sem = normalizedSemantic[blockId] ?? 0.0
       let hybrid = effectiveAlpha * kw + (1 - effectiveAlpha) * sem
       // cap at 1.0 (in case of exact match boost overflow)
       results.append(RankedResult(blockId: blockId, hybridScore: min(hybrid, 1.0)))
   }
   ```

8. **Sort** by `hybridScore` descending.

9. **No threshold on hybrid score.** Both individual engines already apply their own thresholds (BM25 threshold for FTS5, cosine >= 0.3 for HNSW). The hybrid ranker works only with results that already passed individual thresholds.

#### 4. `BreadcrumbBuilder`

Location: `Noto/Search/BreadcrumbBuilder.swift`

Walks a block's ancestor chain and produces a display string.

```swift
struct BreadcrumbBuilder {
    func build(for block: Block) -> String
}
```

**Algorithm:**
1. Start with the block's parent (not the block itself — the block's content is shown as the title)
2. Walk up the parent chain, collecting each ancestor's content
3. For each ancestor's content: take the first line, truncate to 30 characters if longer, append "..." if truncated
4. Reverse the collected array (root-first order)
5. Replace the top-level root's content with "Home" (root blocks have `parent == nil`)
6. Join with " / "

```swift
func build(for block: Block) -> String {
    var ancestors: [String] = []
    var current = block.parent
    while let ancestor = current {
        let title = ancestor.content.components(separatedBy: "\n").first ?? ""
        let truncated = title.count > 30 ? String(title.prefix(30)) + "..." : title
        ancestors.append(truncated)
        current = ancestor.parent
    }
    ancestors.reverse()
    // Replace the root with "Home"
    if !ancestors.isEmpty {
        ancestors[0] = "Home"
    }
    return ancestors.joined(separator: " / ")
}
```

**Example outputs:**
- Root-level block → `"Home"`
- One level deep → `"Home / Not too bad"`
- Two levels deep → `"Home / Not too bad / but this is a bullet"`

#### 5. `SearchSheet` (SwiftUI View)

Location: `Noto/Views/SearchSheet.swift`

Bottom sheet with search bar, "Ask AI" row, and results list.

```swift
struct SearchSheet: View {
    @Environment(\.dismiss) var dismiss
    @State private var queryText: String = ""
    @State private var results: [SearchResult] = []
    @State private var isSearching: Bool = false
    @State private var isIndexing: Bool = false

    let searchService: SearchService
    let onSelectResult: (Block) -> Void  // callback to navigate
    let onAskAI: (String) -> Void        // callback for AI chat
}
```

**View layout:**

```
Sheet (presented as .sheet with detents)
├── Grabber (built into sheet presentation)
├── VStack
│   ├── Ask AI Row (visible when queryText is not empty)
│   │   ├── AI icon (SF Symbol)
│   │   └── Text: "Ask AI \"{queryText}\""
│   │
│   ├── Section Header: "Results" (visible when results exist)
│   │
│   ├── ScrollView / List
│   │   └── ForEach(results) { result in
│   │       SearchResultRow(result: result)
│   │           .onTapGesture { onSelectResult(block) }
│   │   }
│   │
│   ├── Spacer
│   │
│   └── Search Bar (bottom, liquid glass style)
│       ├── Search icon (SF Symbol: magnifyingglass)
│       ├── TextField (placeholder: "Search or ask anything")
│       ├── Clear button (X) — visible when text is non-empty
│       └── Submit button (arrow.up.circle.fill) — triggers search
```

**Sheet presentation:**
```swift
// In ContentView or the presenting view:
.sheet(isPresented: $showSearch) {
    SearchSheet(
        searchService: searchService,
        onSelectResult: { block in
            showSearch = false
            navigateToBlock(block)
        },
        onAskAI: { query in
            // Future: navigate to AI chat with query
        }
    )
    .presentationDetents([.large])
    .presentationDragIndicator(.visible)
}
```

**Behavior:**
- `onAppear`: call `searchService.ensureIndexFresh()`, set `isIndexing = true` while running
- Submit button action: set `isSearching = true`, call `searchService.search(rawQuery: queryText)`, set results, set `isSearching = false`
- Clear button: set `queryText = ""`, clear `results`
- Keyboard: auto-focus the text field on appear

#### 6. `SearchResultRow` (SwiftUI View)

Location: `Noto/Views/SearchResultRow.swift`

```swift
struct SearchResultRow: View {
    let result: SearchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(result.content)
                .font(.system(size: 17))
                .foregroundStyle(.primary)
                .lineLimit(nil)  // wrap for long blocks

            Text(result.breadcrumb)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
    }
}
```

Row height is 68pt per the Figma design, with content vertically centered. Standard iOS separator between rows.

---

## Navigation on Result Tap

When the user taps a search result, the app needs to navigate to that block within its note tree. This uses the existing `NavigationStack(path: $navigationPath)` pattern in `ContentView`.

**Algorithm:**
1. Fetch the `Block` from SwiftData by `result.id`
2. Build the full ancestor path (same walk as BreadcrumbBuilder, but keeping Block references):
   ```swift
   var path: [Block] = []
   var current: Block? = block
   while let b = current {
       path.insert(b, at: 0)
       current = b.parent
   }
   ```
3. Dismiss the search sheet
4. Set `navigationPath = path` on ContentView

This is the same pattern used by `navigateToToday()` in `ContentView.swift:158-168`. The search sheet communicates the selected block back to ContentView via the `onSelectResult` callback, which then builds and sets the navigation path.

---

## Dirty Flush on Sheet Appear

The flush runs when the search sheet appears, before the user submits a query.

```swift
.onAppear {
    Task {
        isIndexing = true
        await searchService.ensureIndexFresh()
        isIndexing = false
    }
}
```

**Small dirty set (typical):** < 100ms — imperceptible, no loading indicator needed.

**Large dirty set (500+ blocks, e.g., first search after long writing session):**
- FTS5 flush: ~100ms (fast)
- Embedding generation: ~15 seconds for 500 blocks (30ms × 500)
- Show a subtle loading indicator while `isIndexing` is true
- The user can still type their query while indexing happens — search is triggered on submit, by which time indexing may have completed
- If the user submits before indexing completes, search runs on whatever is indexed so far (stale but not empty)

---

## File Structure

```
Noto/Search/
├── DateFilterParser.swift     # Temporal phrase extraction
├── SearchService.swift        # Orchestration — the single search entry point
├── HybridRanker.swift         # Score normalization + combination
├── BreadcrumbBuilder.swift    # Ancestor path display string

Noto/Views/
├── SearchSheet.swift          # Bottom sheet with search bar + results
├── SearchResultRow.swift      # Single result row view
```

---

## Integration Points

### 1. Presenting the Search Sheet

Add a search button to ContentView's toolbar (or the bottom bar per the Figma design). On tap, present the search sheet:

```swift
@State private var showSearch = false

// In toolbar or bottom bar:
Button { showSearch = true } label: { Image(systemName: "magnifyingglass") }

.sheet(isPresented: $showSearch) {
    SearchSheet(
        searchService: searchService,
        onSelectResult: { block in
            showSearch = false
            navigateToBlock(block)
        },
        onAskAI: { query in /* future */ }
    )
}
```

### 2. Navigation to Search Result

Add a `navigateToBlock(_ block: Block)` method to ContentView (mirrors `navigateToToday()`):

```swift
private func navigateToBlock(_ block: Block) {
    var path: [Block] = []
    var current: Block? = block
    while let b = current {
        path.insert(b, at: 0)
        current = b.parent
    }
    navigationPath = path
}
```

### 3. SearchService Initialization

The `SearchService` is created once and shared. It holds references to all the indexing and search components:

```swift
// In NotoApp or a dependency container:
let fts5Database = FTS5Database(directory: appSupportDir)
let dirtyTracker = DirtyTracker(fts5Database: fts5Database)
let fts5Indexer = FTS5Indexer(fts5Database: fts5Database, modelContext: bgContext)
let fts5Engine = FTS5Engine(fts5Database: fts5Database)
let embeddingModel = try EmbeddingModel()
let hnswIndex = HNSWIndex(path: vectorIndexPath)
let embeddingIndexer = EmbeddingIndexer(embeddingModel: embeddingModel, hnswIndex: hnswIndex, modelContext: bgContext)
let semanticEngine = SemanticEngine(embeddingModel: embeddingModel, hnswIndex: hnswIndex)

let searchService = SearchService(
    dirtyTracker: dirtyTracker,
    fts5Indexer: fts5Indexer,
    embeddingIndexer: embeddingIndexer,
    fts5Engine: fts5Engine,
    semanticEngine: semanticEngine,
    dateFilterParser: DateFilterParser(),
    hybridRanker: HybridRanker(),
    modelContext: bgContext
)
```

Injected into views via SwiftUI environment or passed directly.

---

## Testing Strategy

### Unit Tests (Swift Testing)

| Test | What it verifies |
|------|-----------------|
| DateFilterParser extracts "today" | Correct date range + stripped query |
| DateFilterParser extracts "last week" | 7-day window |
| DateFilterParser extracts "in March 2024" | Month range |
| DateFilterParser returns nil for no temporal phrase | No false positives |
| DateFilterParser strips phrase from query | "notes from today" → "notes" |
| HybridRanker normalizes BM25 scores to [0,1] | Normalization math |
| HybridRanker normalizes cosine similarity to [0,1] | Normalization math |
| HybridRanker: both-engine results rank highest | Hybrid weighting |
| HybridRanker: keyword-only caps at 0.6 | Missing semantic score = 0 |
| HybridRanker: semantic-only caps at 0.4 | Missing keyword score = 0 |
| HybridRanker: empty keyword → pure semantic (α=0) | Short-circuit |
| HybridRanker: single result gets score 1.0 | Single-result normalization |
| HybridRanker: exact match boost applied | Verbatim match detection |
| BreadcrumbBuilder: root block → "Home" | Root handling |
| BreadcrumbBuilder: nested block → correct path | Multi-level ancestors |
| BreadcrumbBuilder: long ancestor title truncated | 30-char limit |

### Integration Tests

| Test | What it verifies |
|------|-----------------|
| End-to-end: create blocks → flush → search → results ranked correctly | Full pipeline |
| Search with date filter returns only blocks in range | Date filtering |
| Search with "today" extracts date and returns today's blocks | Date parsing + search |
| Result tap navigates to correct block | Navigation integration |
| Dirty flush on sheet appear indexes pending blocks | Flush trigger |

### UI Tests (XCUITest)

| Test | What it verifies |
|------|-----------------|
| Search sheet presents on button tap | Sheet presentation |
| Type query + submit → results appear | Basic search flow |
| Tap result → sheet dismisses, block visible | Navigation works |
| Clear button clears text and results | Clear functionality |
| "Ask AI" row shows query text | AI row display |

---

## Performance Considerations

- **Parallel search:** FTS5 and HNSW run concurrently via `async let`. Total search time is max(FTS5, HNSW) + ranking, not sum.
- **Breadcrumb is O(depth):** Walking the parent chain for each result. Typical depth is 3-5 levels, so < 1ms per result. For 50 results: ~50ms total. Could cache if this becomes a bottleneck.
- **Batch block fetch:** When building SearchResults, fetch all needed blocks in one SwiftData query rather than one-by-one.
- **Lazy result rendering:** The SwiftUI List only renders visible rows. Breadcrumbs for off-screen results aren't computed until scrolled into view (if using `LazyVStack`).
