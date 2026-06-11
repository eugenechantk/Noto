# Feature: header-touch-targets

## User Story

On iPhone and iPad, the header action buttons in the file view (new note, sort, more) and the sidebar (back, new folder, more) are hard to tap — their hit targets are only as big as the glyph (~20×20pt). They should meet the Apple HIG 44×44pt minimum without changing the visual design.

## User Flow

1. Open the app on iPhone → file view top bar shows ‹ back · new-note · sort · more.
2. Open the app on iPad → sidebar header shows ‹ back · new-folder · more.
3. Tapping anywhere within ~44×44pt around each glyph triggers the action.

## Success Criteria

- SC1: File view top bar buttons (new note, sort menu, more menu, back) each have a hit target ≥ 44×44pt.
- SC2: Sidebar header buttons (new folder, more menu, back) each have a hit target ≥ 44×44pt.
- SC3: Visual layout is essentially unchanged — glyph positions, header heights, and spacing stay where they are (small ±few-pt drift acceptable).
- SC4: Menus (sort, more) still open; actions (new note, new folder, back) still fire.

## Test Strategy

Pure view-layout change — no business logic, reducers, or transforms touched, so no new Swift tests apply (per /ios-testing, nothing deterministic to assert). Acceptance is simulator-based:
- Accessibility frame inspection (UI snapshot) proves element bounds ≥ 44×44.
- Off-center taps (≈15pt from glyph center) prove the expanded targets respond.
- Screenshots prove the visual layout is unchanged.

## Tests

- None (no logic change). Existing package suites run as regression check.

## Implementation Details

- `Noto/Views/NoteListView.swift` `topBar`: give each trailing button label a 44×44 frame + `contentShape(Rectangle())`; HStack spacing 18→0 and trailing padding tuned so glyph positions stay put (bar is 48pt tall, so 44pt buttons fit). Back button gets `minHeight: 44` + contentShape.
- `Noto/Views/Shared/NotoSidebarView.swift` `vaultSidebarHeader`: same 44×44 frames on new-folder + ellipsis labels; trailing HStack capped at its current 22pt layout height so the header doesn't grow — the buttons overflow invisibly and remain tappable. Back button gets `minHeight: 44`.

## Residual Risks

- Hit-target overflow beyond the sidebar nav row's layout bounds relies on SwiftUI not clipping hit tests to parent frames (it doesn't, absent `.clipped()`); verified live in simulator.

## Bugs

_None yet._
