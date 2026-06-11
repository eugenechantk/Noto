# Feature: search-folder-filter

## User Story

In AI chat, Eugene wants queries like "what did I save in the last 5 days in the Captures folder" to search **only notes inside that folder**. The chat `search` tool already supports date filters; it needs a folder filter that restricts both the keyword and semantic legs.

## User Flow

1. User asks the chat a question scoped to a folder ("…in the Captures folder").
2. The model calls `search` with `query`, date filters, and `folder: "Captures"`.
3. Results come only from `Captures/**`; the result header names the folder so the model (and user) can see the filter was applied.

## Success Criteria

- SC1: ✅ Keyword search (notes + sections legs) returns only results whose vault-relative path is inside the given folder. Subfolders included ("Captures" matches `Captures/Sub/x.md`); root notes excluded; sibling folders with a shared name prefix excluded ("Cap" must not match `Captures/…`). — `testKeywordSearchFiltersByFolder`, `testHybridRunFiltersBothLegs`
- SC2: ✅ The semantic leg respects the same filter (hits outside the folder are dropped before fusion). — `testHybridRunFiltersBothLegs` (semantic-only hit outside folder dropped, inside kept)
- SC3: ✅ Folder input is forgiving: whitespace/slashes normalized; matching case-insensitive and segment-safe. — `testNormalizationAndMatching`, slashed-input case in `testKeywordSearchFiltersByFolder`
- SC4: ✅ The chat `search` tool exposes `folder`, passes it through the provider, and names it in the output incl. no-results. — `testFolderArgumentReachesProvider`, `testFolderAppearsInOutputAndNoResultsMessage`
- SC5: ✅ No filter → behavior unchanged. — `testNoFolderFilterBehaviorUnchanged`

**Verification runs (2026-06-11):** NotoSearch 119/119 (excl. live-vault suite), NotoChat 42/42 (excl. live suites), app builds clean for iOS simulator and macOS.

## Test Strategy

All logic is package-level (NotoSearch SQL + matcher, NotoChat tool parsing/formatting) — proven with `swift test`, no simulator needed. The chat surface change is non-visual (tool schema), so per /ios-development no simulator validation is required; one live chat sanity check on simulator is a bonus, not a gate.

## Tests

### Package — NotoSearch (`SearchFolderFilterTests.swift`)
- `keywordSearchFiltersNotesByFolder` — SC1 (notes leg, subfolder included, root + prefix-sibling excluded)
- `keywordSearchFiltersSectionsByFolder` — SC1 (sections leg)
- `folderPrefixNormalizationAndMatching` — SC3
- `hybridKeywordOnlyRunRespectsFolderFilter` — SC1/SC5 via `HybridNoteSearch.run` with `embedQuery` returning nil
- `semanticHitsOutsideFolderAreDropped` — SC2 (matcher-level on `SemanticSearchHit.relativePath`)

### Package — NotoChat (`VaultToolsSearchTests` additions or new file)
- `searchToolParsesFolderArgument` — SC4 (spy provider receives folder)
- `searchToolFormatsFolderInOutput` — SC4

## Implementation Details

- `NotoSearch/SearchUtilities`: `normalizedFolderPrefix(_:)` + `isPath(_:inFolder:)` (case-insensitive, segment-safe prefix match) shared by both legs and tests.
- `SearchIndexStore.search(..., folderPrefix: String? = nil)`: SQL `AND n.relative_path LIKE '<escaped prefix>/%' ESCAPE '\'` on both note and section legs (SQLite LIKE is ASCII case-insensitive).
- `HybridNoteSearch.Request.folderPrefix` → keyword leg via store, semantic leg via post-filter on `hit.relativePath` before RRF fusion.
- `NotoChat`: `ChatSearchRequest.folder`, `folder` property in the tool schema (description tells the model to use `list` to discover folder names), parse in `runSearch`, surface in `format`.
- App: `HybridChatSearchProvider` passes `request.folder` through.

## Residual Risks

- The model choosing the right folder name relies on the schema description + `list` tool; not deterministically testable.
- In-app search sheet doesn't expose the folder filter (not requested).

## Bugs

_None yet._
