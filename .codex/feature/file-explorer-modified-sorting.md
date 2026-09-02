# Feature: File Explorer Modified-Date Sorting

## User Story

As a Noto user browsing files, I want folders grouped first and pages ordered by most recently edited so the pages I am actively working on are easiest to reach.

## User Flow

1. Open Browse at the vault root or inside any folder.
2. See every folder before every page.
3. See pages ordered from latest edited to earliest edited.
4. When pages have the same edit date, see a stable title/path order rather than list jitter.

## Success Criteria

- SC1: Every Browse directory groups folders before pages.
- SC2: Folders remain ordered by localized natural name order.
- SC3: Pages are ordered by `modifiedDate` descending.
- SC4: Pages with equal edit dates use display title, then path, as deterministic ascending tie-breakers.
- SC5: Untitled pages still display and tie-break using their filename.
- SC6: Existing Browse navigation and row presentation remain unchanged.

## Test Strategy

- App-target Swift Testing exercises the pure `ExplorerSorting` function with mixed folders/pages, reversed input, equal timestamps, and untitled notes.
- The complete Noto 2 test bundle guards Browse and startup regressions.
- FlowDeck simulator evidence verifies the seeded Browse list visibly groups folders first and orders note rows newest-to-oldest.

## Tests

### App unit

- `Noto2Tests/ExplorerSortingTests.swift`
  - folders first, folders by name, pages by modified date descending — SC1, SC2, SC3.
  - equal-date pages use title then path — SC4.
  - untitled pages use filename — SC5.
  - reversing input produces the same output — SC4.

## Implementation Details

- Keep sorting in the pure Noto 2 `ExplorerSorting` seam used by every `FolderListView`.
- Do not alter row rendering or storage loading.
- `modifiedDate` descending is the primary page comparator.
- Equal timestamps fall back to localized natural display-title ordering and then standardized file path.

## Residual Risks

- Equal-date and untitled-page tie-break behavior is covered by unit tests but was not separately exercised in the visual audit.

## Verification

- Red test: the prior title sorter failed the modified-date and equal-date/path cases.
- Focused `ExplorerSortingTests`: 4/4 passed after implementation.
- Full Noto 2 Swift Testing bundle: 31/31 passed.
- FlowDeck build/install/launch: passed on isolated iPhone simulator.
- Root Browse screenshot: `.codex/evidence/file-explorer-modified-sorting/root-order.png`.
- Nested Browse screenshot: `.codex/evidence/file-explorer-modified-sorting/nested-order.png`.
- Independent visual audit: PASS. Root and nested folder ordering, navigation return, and row presentation matched the success criteria. Report: `.codex/evidence/20260829-151812-ios-visual-audit/evidence.md`.

## Bugs

- None yet.
