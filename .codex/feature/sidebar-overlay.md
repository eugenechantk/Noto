# Feature: Sidebar Overlay

## User Story

On iPadOS regular-width layouts and macOS, opening the sidebar should place it over the editor instead of reducing editor width through a split view.

## Success Criteria

- iPadOS regular-width Noto sidebar appears as a leading overlay above the editor content.
- macOS Noto sidebar appears as a leading overlay above the editor content.
- Editor content keeps full-window width behind the sidebar.
- Existing sidebar selection, search, and toggle commands continue to work.

## Test Strategy

- Build the app with FlowDeck to verify SwiftUI changes compile.
- Run focused tests if available for affected navigation state.
- Use simulator validation for iPadOS UI if the build environment supports it.

## Implementation Details

- Use the native `NavigationSplitView` implementation instead of a custom overlay.
- Set regular-width iPadOS and macOS split views to `.navigationSplitViewStyle(.prominentDetail)`, which asks SwiftUI to preserve detail content size while showing/hiding the sidebar.
- Keep `backgroundExtensionEffect()` on macOS detail content only. Do not use it on iPadOS because it causes the top bar to reflect content underneath.
- Use native SwiftUI `List(selection:)` with `.listStyle(.sidebar)` for the shared sidebar instead of custom `ScrollView` rows.
- Tighten native list layout with row insets, `defaultMinListRowHeight`, and iOS-only `listRowSpacing(0)`. Apple documents these as the supported SwiftUI list layout controls; there is not a separate tighter iPad sidebar list style.
- Start iPadOS regular-width split views in `.detailOnly` and collapse back to `.detailOnly` after selecting or creating a note from the sidebar.

## Residual Risks

- macOS was verified by build and one Appium screenshot after deterministic install.
- iPadOS was visually verified in Simulator with a seeded vault for initial hidden sidebar, native overlay sidebar, compact row styling, and note selection hiding the sidebar.
