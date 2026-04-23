# Feature: Sidebar Deep Title Search

## User Story

As a macOS Noto user, I want sidebar search to find note titles across the whole vault so collapsed folders do not hide matching notes.

## User Flow

1. Collapse a folder in the sidebar.
2. Open sidebar search.
3. Type a note title that lives under the collapsed folder.
4. See the matching note with its ancestor folders in the result list.

## Success Criteria

- [x] Sidebar search matches note titles whether or not their folders are currently expanded.
- [x] Search results include ancestor folders for matching nested notes.
- [x] Searching does not mutate the user's persisted folder expansion state.

## Test Strategy

Use `NotoVault` Swift Testing coverage for the tree-loader behavior that powers the shared sidebar.

## Tests

- `Packages/NotoVault/Tests/NotoVaultTests/SidebarTreeLoaderTests.swift`
  - `searchRowsIgnoresCollapsedFolderExpansionState` verifies all success criteria at the loader layer.

## Implementation Details

Keep separate sidebar row snapshots:

- visible rows: loaded with the user's persisted expansion state
- searchable rows: loaded fully expanded and only used while search text is non-empty

## Residual Risks

The package test proves the search data source behavior. The macOS app build passed, but this was not manually exercised in a running macOS window during this turn.

## Bugs

None yet.
