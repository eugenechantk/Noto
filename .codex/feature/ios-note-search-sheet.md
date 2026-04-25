# Feature: iOS Note Search Sheet

## User Story

As an iPhone or iPad Noto user, I want the bottom-bar Search button to open a full-size sheet where I can search notes by title and open a result.

## User Flow

1. Tap Search in the bottom toolbar.
2. A full-size sheet appears with a search field at the top.
3. Type a title query.
4. Matching notes appear in the same note-list row style.
5. Tap a note to dismiss the sheet and open that note.

## Success Criteria

- [x] The bottom-bar Search button opens a full-size sheet on iOS and iPadOS.
- [x] Search is title-only and case-insensitive for now, matching the current macOS sidebar search behavior.
- [x] The sheet uses a search field and note list presentation consistent with the existing mention-note sheet and note list rows.
- [x] Selecting a result opens the note in the active iOS/iPadOS navigation mode.

## Test Strategy

- Add focused unit coverage for title-search result behavior if new pure logic is introduced.
- Build iOS with FlowDeck and validate the sheet in Simulator because this changes navigation and presentation.

## Tests

- `flowdeck build --json` passed for iOS Simulator.
- `flowdeck run -S "Noto-SearchSheet-iPhone-temp" --json` installed and launched the app on an isolated iPhone simulator.
- `.maestro/seed-vault.sh 68369241-781C-4CBE-BA82-CEC48B27F4AA` seeded the iPhone simulator vault.
- FlowDeck UI automation on `Noto-SearchSheet-iPhone-temp` verified Search opens the sheet, `Shop` filters to `Shopping List`, and tapping the result opens the editor.
- `flowdeck run -S "Noto-SearchSheet-iPadMini-temp" --json` installed and launched the app on an isolated iPad mini simulator.
- `.maestro/seed-vault.sh 00A08A6A-079C-4CDD-B0C1-C829E59707A3` seeded the iPad mini simulator vault.
- FlowDeck UI automation on `Noto-SearchSheet-iPadMini-temp` verified the full-width page-style sheet, `Shop` filters to `Shopping List`, and tapping the result opens the editor.
- `flowdeck build -D "My Mac" --json` passed as a shared-file guardrail.

## Implementation Details

- Reuse `SidebarTreeLoader` to load vault-wide rows.
- Filter to note rows for the iOS search sheet.
- Use the existing compact and split note-opening paths instead of adding a separate navigation model.

## Residual Risks

None known for the scoped title-search sheet. Full-text note search is intentionally out of scope for this version.

## Bugs

None yet.
