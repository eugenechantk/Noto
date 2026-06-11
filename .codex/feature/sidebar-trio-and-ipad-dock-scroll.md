# Feature: sidebar-trio-and-ipad-dock-scroll

Two requests from Eugene (2026-06-10):
1. "the sidebar buttons on ipados and macos should be the same as the file view top buttons (new note, sort, and more actions)"
2. "the bottom bar does not hide when scrolling the document down, and appears again when scrolling the document up on ipados, like the iphone os"

## Change 1 — Sidebar header action trio (iPadOS + macOS)

`NotoSidebarView.vaultSidebarHeader` previously showed new-folder + ⋯ more. It now shows the same trio as the file view top bar:
- **New note** (`square.and.pencil`, 18pt) → `.createNote(in: currentStore)` (creates in the currently shown folder)
- **Sort** (`line.3.horizontal.decrease`, 17pt) → Recent / Name picker, new `@State sort` passed into both `DirectoryContentListView` calls (param already existed)
- **More** (`ellipsis`, 18pt) → New Folder · AI Chat · Settings (New Note left the menu since it's now a first-class button; New Folder moved in)

All three keep the 44×44pt hit targets from the touch-target work. Shared view → applies to iPadOS and macOS alike.

## Change 2 — iPad dock hides on scroll

The scroll-driven hide/show logic already existed in `NoteEditorScreen` (`setDockHidden`, ±6pt jitter threshold, reveal near top) but only drove the iPhone-compact editor dock. On iPad the dock is owned by `NotoSplitView`, which never received the signal.

Plumbing: `NoteEditorScreen.onDockScrollHiddenChange` (new optional callback, fired from `setDockHidden`) → `VaultWorkspaceView.setSplitDockHidden` (new `@State splitDockHiddenByScroll`, same animation curves) → `NotoSplitView.dockHiddenByScroll` (new param) → `notoAppBottomToolbar(hiddenByScroll:)` (param already existed). Dock visibility resets when the selected note changes. iPhone passes no callback — behavior unchanged. macOS ignores the dock param entirely.

## Success Criteria

- SC1: iPad sidebar header shows new-note / sort / more with 44×44 frames. ✅ verified (frames + screenshot)
- SC2: Sidebar sort menu shows Recent/Name; more menu shows New Folder/AI Chat/Settings. ✅ verified
- SC3: Sidebar new-note button creates a note in the current sidebar folder. (auditor)
- SC4: iPad: scrolling a long note down hides the dock; scrolling up reveals it. ✅ verified via accessibility tree (dock absent after scroll down, present after scroll up)
- SC5: iPhone file view + dock behavior unchanged. ✅ frames re-verified after rebuild
- SC6: macOS builds with the shared sidebar change. ✅ `flowdeck build -D "My Mac"` succeeded

## Tests

- No new unit tests: pure chrome wiring over existing tested sort logic (`DirectoryContentListView.displayedItems`) and existing scroll-hide logic. `NotoTests/NoteListViewTests` re-run: 2/2 pass.

## Residual Risks

- macOS sidebar trio not visually verified in this session (compiles; same SwiftUI code path verified on iPad; macOS-specific menu styling via `.menuStyle(.borderlessButton)` retained).
- Multi-scene iPad (two Noto windows): dock state is per-window (`@State`), no cross-window leakage expected.
