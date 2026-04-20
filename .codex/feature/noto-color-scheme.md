# Feature: Noto Color Scheme

## User Story

As a Noto user, the app should feel like a focused monochrome writing environment with consistent text, background, and separator colors.

## User Flow

- The app uses a dark monochrome palette across the note list, editor, setup, and settings screens.
- Editor text uses the same foreground/background palette as the app shell.
- System toolbar controls keep their native behavior while using the app tint.

## Success Criteria

- SC1: The app background uses `#0A0A0A`.
- SC2: Primary text and tint use `#E5E5E5`.
- SC3: Secondary text uses `#D4D4D4`.
- SC4: Muted markdown syntax uses `#525252`.
- SC5: Separators and low-emphasis surfaces use `#27272A`.
- SC6: The palette stays monochrome; no additional brand color is introduced.

## Test Strategy

This is visual styling plus a small shared theme layer. Build catches API issues; simulator validation checks that the note list and editor actually render with the new dark palette.

## Tests

- `flowdeck build`
- `flowdeck build -D "My Mac"`
- `flowdeck run -S A191DEF2-4816-48D4-B59F-DED26FFAD8A6 --json`
- Seeded vault with `.maestro/seed-vault.sh A191DEF2-4816-48D4-B59F-DED26FFAD8A6`
- Visual inspection in FlowDeck session `32D0C03E-7765-4FA0-AC25-B6F2A1009D94` for the note list and editor palette.

## Implementation Details

`AppTheme` owns the semantic color tokens and platform color bridges. The app forces a dark color scheme, applies the monochrome tint at the root, and uses the same tokens in SwiftUI screens and the active TextKit 2 editor.

## Residual Risks

Exact system toolbar material colors remain owned by iOS so they can preserve native toolbar behavior.

## Bugs

None yet.
