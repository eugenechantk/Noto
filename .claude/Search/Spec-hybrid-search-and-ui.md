# Spec: Hybrid Search API + Search UI

Based on [PRD-hybrid-search-and-ui.md](./PRD-hybrid-search-and-ui.md).

**Dependencies:**
- Spec-search-foundation (FTS5Database, DirtyTracker, DateRange)
- Spec-keyword-search (FTS5Engine, FTS5Indexer, KeywordSearchResult)
- Spec-semantic-search (SemanticEngine, EmbeddingIndexer, SemanticSearchResult)

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
│ 1. Flush dirty     │ → DirtyTracker (foundation) + FTS5Indexer (keyword) + EmbeddingIndexer (semantic)
│ 2. Parse date      │ → DateFilterParser
│ 3. Parallel search │ → FTS5Engine (keyword) + SemanticEngine (semantic)
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
    let dateRange: DateRange? // optional date filter (from foundation)
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

**No cross-PRD dependencies — can be built in parallel with any phase.**

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
   Use `NSDataDetector` with `.date` checking type, then compute the full month/year range.

3. Scan the raw query against all patterns (case-insensitive).

4. If a match is found:
   - Compute the `DateRange`
   - Remove the matched substring from the query
   - Trim whitespace from remaining text
   - Return `SearchQuery(text: cleanedText, dateRange: range)`

5. If no match: return `SearchQuery(text: rawQuery, dateRange: nil)`

**Edge cases:**
- Multiple temporal phrases: use the first match (leftmost)
- Empty text after stripping: return empty text (triggers date-only path in SearchService)
- Ambiguous phrases like "march" (could be month or verb): patterns are anchored to common phrasing ("in March", "last March") — bare "march" is not matched

#### 2. `SearchService`

Location: `Noto/Search/SearchService.swift`

**Depends on: FTS5Engine (keyword), SemanticEngine (semantic), DirtyTracker (foundation), FTS5Indexer (keyword), EmbeddingIndexer (semantic).**

Orchestrates the full search pipeline. Single entry point for search.

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

    func search(rawQuery: String) async -> [SearchResult]
    func ensureIndexFresh() async
}
```

**`ensureIndexFresh()` algorithm:**
1. `await dirtyTracker.flush()` — persist in-memory dirty set
2. Fetch all dirty blocks from `dirty_blocks` table
3. Run FTS5 and embedding indexing for dirty blocks
4. Save HNSW index

**`search()` algorithm:**
1. Parse date filter: `dateFilterParser.parse(rawQuery)` → `SearchQuery`
2. If `query.text` is empty and `query.dateRange` is nil, return `[]`
3. **Short-circuit: empty text with date range** — if text is empty but dateRange set (e.g., "today"), skip FTS5/semantic. Fetch all blocks in date range from SwiftData, return sorted by `updatedAt` descending.
4. Run keyword and semantic search in parallel:
   ```swift
   async let keywordResults = fts5Engine.search(query:, dateRange:, modelContext:)
   async let semanticResults = semanticEngine.search(query:, dateRange:, modelContext:)
   ```
5. Pass both result sets to `hybridRanker.rank(keyword:, semantic:)`
6. For each ranked result, build breadcrumb + fetch content:
   - Fetch `Block` from SwiftData by ID
   - Get `block.content` for display
   - Call `BreadcrumbBuilder.build(for: block)` for the breadcrumb string
7. Return `[SearchResult]` sorted by `hybridScore` descending

#### 3. `HybridRanker`

Location: `Noto/Search/HybridRanker.swift`

**No cross-PRD dependencies — can be built in parallel with any phase.**

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
   - If keyword results are empty: `effectiveAlpha = 0.0` (pure semantic)
   - If semantic results are empty: `effectiveAlpha = 1.0` (pure keyword)
   - Otherwise: `effectiveAlpha = alpha` (0.6)

6. **Exact match boost:**
   - For each keyword result, check if query text appears verbatim in block content (case-insensitive)
   - If yes: multiply normalized keyword score by 1.5 (capped at 1.0 after combination)

7. **Compute hybrid scores:**
   ```swift
   for blockId in allBlockIds {
       let kw = normalizedKeyword[blockId] ?? 0.0
       let sem = normalizedSemantic[blockId] ?? 0.0
       let hybrid = effectiveAlpha * kw + (1 - effectiveAlpha) * sem
       results.append(RankedResult(blockId: blockId, hybridScore: min(hybrid, 1.0)))
   }
   ```

8. **Sort** by `hybridScore` descending.

9. **No threshold on hybrid score.** Both individual engines already apply their own thresholds.

#### 4. `BreadcrumbBuilder`

Location: `Noto/Search/BreadcrumbBuilder.swift`

**Depends only on Block model (existing) — can be built in parallel with any phase.**

Walks a block's ancestor chain and produces a display string.

```swift
struct BreadcrumbBuilder {
    static func build(for block: Block) -> String
}
```

**Algorithm:**
1. Start with the block's parent (not the block itself)
2. Walk up the parent chain, collecting each ancestor's content
3. For each: take first line, truncate to 30 characters + "..." if longer
4. Reverse (root-first order)
5. Replace the top-level root's content with "Home"
6. Join with " / "

**Examples:**
- Root-level block → `"Home"`
- One level deep → `"Home / Not too bad"`
- Two levels deep → `"Home / Not too bad / but this is a bullet"`

#### 5. `SearchSheet` (SwiftUI View)

Location: `Noto/Views/SearchSheet.swift`

**Depends on: SearchService.**

Bottom sheet with search bar, "Ask AI" row, and results list.

```swift
struct SearchSheet: View {
    @Environment(\.dismiss) var dismiss
    @State private var queryText: String = ""
    @State private var results: [SearchResult] = []
    @State private var isSearching: Bool = false
    @State private var isIndexing: Bool = false

    let searchService: SearchService
    let onSelectResult: (Block) -> Void
    let onAskAI: (String) -> Void
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
│       ├── Search icon (magnifyingglass)
│       ├── TextField (placeholder: "Search or ask anything")
│       ├── Clear button (X) — visible when text is non-empty
│       └── Submit button (arrow.up.circle.fill) — triggers search
```

**Behavior:**
- `onAppear`: call `searchService.ensureIndexFresh()`, set `isIndexing` while running
- Submit: set `isSearching`, call `searchService.search(rawQuery:)`, display results
- Clear: reset `queryText` and `results`
- Keyboard: auto-focus text field on appear

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
                .lineLimit(nil)

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

---

## Navigation on Result Tap

Same pattern as `navigateToToday()` in `ContentView.swift`:

1. Fetch `Block` by `result.id`
2. Walk ancestor chain:
   ```swift
   var path: [Block] = []
   var current: Block? = block
   while let b = current {
       path.insert(b, at: 0)
       current = b.parent
   }
   ```
3. Dismiss search sheet
4. Set `navigationPath = path`

---

## Dirty Flush on Sheet Appear

```swift
.onAppear {
    Task {
        isIndexing = true
        await searchService.ensureIndexFresh()
        isIndexing = false
    }
}
```

Small dirty set (< 100 blocks): < 100ms — imperceptible.
Large dirty set (500+ blocks): show loading indicator while `isIndexing`.

---

## Integration Points

### 1. Presenting the Search Sheet

```swift
@State private var showSearch = false

.sheet(isPresented: $showSearch) {
    SearchSheet(
        searchService: searchService,
        onSelectResult: { block in
            showSearch = false
            navigateToBlock(block)
        },
        onAskAI: { query in /* future */ }
    )
    .presentationDetents([.large])
    .presentationDragIndicator(.visible)
}
```

### 2. Navigation to Search Result

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

```swift
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

---

## File Structure

```
Noto/Search/
├── DateFilterParser.swift     # Temporal phrase extraction
├── SearchService.swift        # Orchestration — single search entry point
├── HybridRanker.swift         # Score normalization + combination

Noto/Views/
├── SearchSheet.swift          # Bottom sheet with search bar + results
├── SearchResultRow.swift      # Single result row view
```

`BreadcrumbBuilder` can live in `Noto/Search/` or `Noto/Views/` — either works.

---

## Testing Strategy

### Design Principle

Three testing layers: (1) unit tests for pure logic (no blocks, no engines), (2) integration tests for the full pipeline (small block fixture), (3) UI tests for sheet interaction (seeded app). Most tests are layer 1.

### Test Helpers

```swift
func makeKeywordResults(_ entries: [(UUID, Double)]) -> [KeywordSearchResult] {
    entries.map { KeywordSearchResult(blockId: $0.0, bm25Score: $0.1) }
}

func makeSemanticResults(_ entries: [(UUID, Float)]) -> [SemanticSearchResult] {
    entries.map { SemanticSearchResult(blockId: $0.0, similarity: $0.1) }
}
```

### Unit Tests (Swift Testing)

#### DateFilterParser

| Test | Input | Expected text | Expected dateRange |
|------|-------|--------------|-------------------|
| "today" | `"notes from today"` | `"notes from"` | start/end of today |
| "yesterday" | `"what I wrote yesterday"` | `"what I wrote"` | yesterday |
| "last week" | `"ideas from last week"` | `"ideas from"` | 7 days ago → now |
| "this week" | `"meetings this week"` | `"meetings"` | start of week → now |
| "last month" | `"projects last month"` | `"projects"` | last month range |
| "this month" | `"tasks this month"` | `"tasks"` | start of month → now |
| "last N days" | `"recent last 3 days"` | `"recent"` | 3 days ago → now |
| "recent" | `"recent thoughts"` | `"thoughts"` | 7 days ago → now |
| "in March" | `"notes in March"` | `"notes"` | March 1-31 |
| "in March 2024" | `"food in March 2024"` | `"food"` | March 1-31 2024 |
| "in 2024" | `"goals in 2024"` | `"goals"` | Jan 1 - Dec 31 2024 |
| No temporal | `"design patterns"` | `"design patterns"` | `nil` |
| False positive | `"march to the beat"` | `"march to the beat"` | `nil` |
| Only temporal | `"today"` | `""` | today's range |
| Multiple (first wins) | `"today and last week"` | `"and last week"` | today's range |
| Case insensitive | `"notes from TODAY"` | `"notes from"` | today's range |

#### HybridRanker

| Test | Keyword | Semantic | Assert |
|------|---------|----------|--------|
| Both-engine highest | A: -5.0, B: -2.0 | A: 0.8 | A has highest hybrid |
| Keyword-only caps at α | A: -5.0 | (none for A) | A's hybrid ≤ 0.6 |
| Semantic-only caps at 1-α | (none for B) | B: 0.9 | B's hybrid ≤ 0.4 |
| Empty keyword → α=0 | `[]` | A: 0.9, B: 0.5 | Pure semantic ranking |
| Empty semantic → α=1 | A: -5.0 | `[]` | Pure keyword ranking |
| Single keyword = 1.0 | A: -3.0 | (none) | A normalized = 1.0 |
| Single semantic = 1.0 | (none) | A: 0.6 | A normalized = 1.0 |
| BM25 normalization | A: -10.0, B: -2.0 | (none) | A > B |
| Cosine normalization | (none) | A: 0.9, B: 0.4 | A=1.0, B=0.0 |
| Exact match boost | A verbatim | same sim | A higher (1.5x) |
| Boost capped | High + boost | - | ≤ 1.0 |
| Disjoint merged | A kw-only, B sem-only | - | Both present |
| Sorted descending | Multiple | - | Monotonic |

#### BreadcrumbBuilder

| Test | Structure | Expected |
|------|-----------|----------|
| Root block | `parent == nil` | `"Home"` |
| One deep | Home → "Projects" → block | `"Home / Projects"` |
| Two deep | Home → "Projects" → "Ideas" → block | `"Home / Projects / Ideas"` |
| Four deep | Home → A → B → C → D → block | `"Home / A / B / C / D"` |
| Long title | Ancestor > 30 chars | Truncated + "..." |
| Multiline | Ancestor "L1\nL2" | Uses "L1" only |
| Self excluded | Block content not in breadcrumb | True |

### Integration Tests

#### SearchTestFixture

```swift
struct SearchTestFixture {
    let container: ModelContainer
    let context: ModelContext
    let searchService: SearchService

    let coffeeBlock: Block       // "The taste of morning coffee is wonderful"
    let designBlock: Block       // "Aesthetic taste in UI design principles"
    let meetingBlock: Block      // "Team meeting to discuss project timeline"
    let shoppingBlock: Block     // "Buy groceries: milk, eggs, bread"
    let deepBlock: Block         // depth 3: Home → Projects → App Ideas → block
    let yesterdayBlock: Block    // createdAt = yesterday
    let lastWeekBlock: Block    // createdAt = 8 days ago
    let lastMonthBlock: Block   // createdAt = 35 days ago
    let shortBlock: Block       // "ok" (< 3 words)
    let codeBlock: Block        // "**Bold** and `inline code` test"

    @MainActor
    static func create() async throws -> SearchTestFixture
}
```

**Block tree:**

```
Home (root)
├── coffeeBlock: "The taste of morning coffee is wonderful"
├── shoppingBlock: "Buy groceries: milk, eggs, bread"
├── shortBlock: "ok"
├── codeBlock: "**Bold** and `inline code` test"
├── Projects/
│   ├── designBlock: "Aesthetic taste in UI design principles"
│   ├── App Ideas/
│   │   └── deepBlock: "Mobile app for tracking habits" (depth 3)
│   └── meetingBlock: "Team meeting to discuss project timeline"
├── Daily Notes/
│   ├── yesterdayBlock (1 day ago)
│   ├── lastWeekBlock (8 days ago)
│   └── lastMonthBlock (35 days ago)
└── "Quantum physics and wave function collapse"
```

#### Integration Test Cases

| Test | Query | Assert |
|------|-------|--------|
| Keyword exact | `"coffee"` | coffeeBlock in results |
| Semantic similarity | `"artistic judgement"` | designBlock found |
| Hybrid ranking | `"taste"` | Both-engine match ranks highest |
| Date: today | `"today"` | Only today's blocks |
| Date: yesterday | `"work yesterday"` | yesterdayBlock only |
| Date: last week | `"review last week"` | lastWeekBlock, not lastMonthBlock |
| Date-only | `"today"` | All today's blocks by recency |
| Short block | `"ok"` | Keyword only, not semantic |
| Markdown stripped | `"Bold"` | codeBlock found |
| Breadcrumb | Find deepBlock | "Home / Projects / App Ideas" |
| No results | `"xyzzy zyxwv"` | Empty |
| Dirty flush | Edit → open → search | Updated content found |

#### Pipeline Tests

| Test | Scenario | Assert |
|------|----------|--------|
| ensureIndexFresh | Mark dirty → ensure | dirty_blocks empty |
| Empty text + dateRange | "today" | Blocks by recency |
| Navigation path | navigateToBlock(deepBlock) | [root, Projects, Ideas, deep] |

### UI Tests (XCUITest)

Launch with `-UITesting` + `SEARCH_TEST_SEED=1`.

```swift
class SearchUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITesting"]
        app.launchEnvironment["UITESTING"] = "1"
        app.launchEnvironment["SEARCH_TEST_SEED"] = "1"
        app.launch()
    }
}
```

| Test | Steps | Assert |
|------|-------|--------|
| Sheet presents | Tap search bar | Sheet visible |
| Search results | Type "coffee" → submit | Result with "coffee" |
| Breadcrumb shown | Type "habits" → submit | Breadcrumb has "Projects" |
| Navigation | Type "coffee" → submit → tap | Sheet dismisses, block visible |
| Clear | Type "test" → clear | Empty text, no results |
| Ask AI row | Type "what is design" | Row with query text |
| Empty results | Type "xyzzy" → submit | No rows |
| Date filter | Type "work yesterday" → submit | Only yesterday's block |
| Search bar position | Open sheet | Input at bottom |

---

## Performance Considerations

- **Parallel search:** FTS5 and HNSW via `async let`. Total = max(FTS5, HNSW) + ranking.
- **Breadcrumb O(depth):** Typical 3-5 levels = < 1ms per result.
- **Batch block fetch:** One SwiftData query for all result blocks, not one-by-one.
- **Lazy rendering:** `LazyVStack` — off-screen breadcrumbs not computed until scrolled.
