# Feature: Noto App Bars

## User Story

As a Noto user, I can access Today and the future search entry point from both the note list and editor, while the editor top bar shows navigable context through a compact breadcrumb.

## User Flow

- In the note list, the bottom toolbar shows the system grouped toolbar with Today, Search, and New Note buttons.
- In the note directory view, top-right actions use native toolbar-group composition.
- In the editor, the top toolbar shows back navigation, a horizontally scrollable breadcrumb, and a more menu.
- In the editor breadcrumb, the current note location is emphasized as the primary breadcrumb button.
- In the editor, the bottom toolbar matches the note list with Today, Search, and New Note.

## Success Criteria

- SC1: iOS note list screens expose Today in the bottom toolbar.
- SC2: iOS note list screens expose a Search button that does nothing yet.
- SC3: iOS editor keeps the renewed top bar with breadcrumb and more menu.
- SC4: iOS editor exposes the same bottom toolbar pattern as the note list.
- SC5: Existing daily note opening behavior is reused.
- SC6: New Note in the bottom toolbar creates a root-vault note and navigates to its editor.
- SC7: Note directory top-right actions use native toolbar items rather than a custom grouped control.
- SC8: The breadcrumb level containing the current note is primary and more emphasized than ancestor levels.

## Test Strategy

This is primarily SwiftUI toolbar composition. Build catches API misuse; simulator validation checks actual toolbar placement and visibility.

## Tests

- `flowdeck build`
- `flowdeck run -S A191DEF2-4816-48D4-B59F-DED26FFAD8A6 --json`
- Seeded vault with `.maestro/seed-vault.sh A191DEF2-4816-48D4-B59F-DED26FFAD8A6`
- Visual inspection in FlowDeck sessions:
  - `3206AD12-4B4C-4853-83A2-C16308AB5864` for the initial pill/search/no-op/new-note pass.
  - `79A01D33-4ECB-430E-AEC9-9366B1A9DD8B` for the no-autofocus New Note adjustment.
  - `4381ABD9-2C37-408B-9CC1-DF7E19A86B8A` for the native system toolbar pass.

## Implementation Details

Use system SwiftUI toolbar groups so iOS owns the toolbar grouping and Liquid Glass styling. `FolderContentView`, the regular-width `SidebarView`, and `NoteEditorScreen` all use the same `notoAppBottomToolbar` modifier for the bottom toolbar. The note directory top-right controls use `ToolbarItemGroup(placement: .navigationBarTrailing)` instead of a custom `HStack`.

The bottom toolbar has three icon buttons:
- Today: opens today's note through the existing `todayNote()` flow.
- Search: no-op placeholder for now.
- New Note: creates a note in `store.vaultRootURL` and navigates/selects that note editor with new-note autofocus.

The editor top bar uses a principal `BreadcrumbBar` and trailing more menu. Compact navigation passes breadcrumb taps back into the existing `NavigationPath`; regular split view keeps the breadcrumb informational for now. The level containing the current note uses primary text and semibold weight, while ancestor levels use muted text and medium weight. Do not wrap the active breadcrumb level in a pill or custom container.

## Residual Risks

Search is intentionally inert for now. Regular-width split view was compiled but not visually checked in this pass; compact note list and editor were visually checked.

## Bugs

None yet.
