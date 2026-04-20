# Feature: macOS + iPadOS Regular UI Redesign, Phases 1-2

## User Story

As a Noto user on macOS or a regular-width iPad, I want a cleaner app chrome and a modern searchable sidebar tree so the editor feels like the primary surface.

## User Flow

1. Open Noto on macOS or iPad regular width.
2. See a split layout with a clean title/chrome area and no Today/Settings toolbar clutter.
3. Use keyboard commands to open Today or Settings.
4. Search folders and notes in the sidebar.
5. Select a note from a flattened folder tree.
6. Toggle folder expansion without disclosure chevrons.

Compact iPhone and compact iPad keep the existing drill-in folder flow.

## Success Criteria

SC1. macOS uses hidden/unified title-bar styling with no custom Today or Settings toolbar items in the split view.

SC2. iPad regular width uses the same shared split presentation and has no custom Today or Settings toolbar items in the navigation chrome.

SC3. Today and Settings are reachable through app commands.

SC4. The shared sidebar shows a search field above a flattened folder/note tree.

SC5. Folder rows toggle expansion in place with folder/document icons and no `DisclosureGroup` chevrons.

SC6. Search is case-insensitive and keeps ancestor folders visible for matching descendants.

SC7. The editor detail root applies the system background-extension effect where available so content can visually flow beneath floating sidebars.

SC8. Compact iOS navigation continues to use `FolderContentView` and `NavigationStack`.

## Test Strategy

Package tests cover the filesystem tree and search-filtering logic. Build verification covers the SwiftUI integration. Visual verification should be done with FlowDeck on macOS/iPad once the app builds.

## Tests

- `Packages/NotoVault/Tests/NotoVaultTests/SidebarTreeLoaderTests.swift`
  - `loadRowsProducesExpandedDepthFirstRows` verifies SC4 and SC5.
  - `filterKeepsAncestorFoldersForDescendantMatches` verifies SC6.
  - `collapsedFoldersHideDescendantRows` verifies SC5.

## Implementation Details

- `NotoApp` configures iOS navigation-bar transparency and app commands.
- `NoteListView` routes macOS and iPad regular width through `NotoSplitView`.
- `NotoSplitView` composes `NotoSidebarView` and the existing `NoteEditorScreen`.
- `NotoSidebarView` renders a search field plus a flattened tree, preserving expansion state in `UserDefaults`.
- `SidebarTreeLoader` lives in `NotoVault` as pure filesystem logic.

## Residual Risks

- Final macOS titlebar/sidebar appearance has build coverage but still needs screenshot-based runtime verification.
- `backgroundExtensionEffect()` availability is OS-gated; older deployment targets keep the existing solid editor background.
- The broader app test suite currently has one unrelated failing TextKit markdown layout test: `TextKit2MarkdownLayoutTests.hyphenBulletsKeepMutedDashMarker()`.

## Bugs

None yet.
