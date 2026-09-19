# Feature: Noto 2 Digest Direct Input

## User Story

As a Noto 2 user processing the Digest, I want each swipe destination to focus its only text input immediately so I can keep typing without an extra tap, and I want redundant action buttons removed.

## User Flow

1. Open the Digest tab with an inbox item.
2. Swipe left to create a new note.
3. The title starts empty, becomes first responder immediately, and accepts typing.
4. Return to the card and swipe right to add the item to an existing note.
5. The search field becomes first responder immediately and accepts typing while note data/results are still loading.
6. Complete either action using the swipe flow; no separate Add to or Create buttons are shown on the Digest card.

## Success Criteria

1. The create destination never autofills a title and focuses the title field when presented.
2. The add-to destination focuses search when presented, independent of asynchronous note loading.
3. The Digest card no longer shows Add to or Create buttons.
4. Swipe actions and their filing behavior remain intact.
5. Changed inputs and screen anchors expose stable accessibility identifiers.

## Test Strategy

- Use Swift Testing for any extracted deterministic presentation/state behavior and existing Digest filing/swipe regressions.
- Use isolated iPhone and iPad simulator verification for focus, keyboard visibility, typing during loading, swipe routing, and the simplified layout.

## Tests

### App Unit — `Noto2Tests/DigestModelTests.swift`

- `addToStartsWithEmptySearchAndSearchFocus` — verifies the add-to initial input/focus contract.
- `createStartsWithEmptyTitleAndTitleFocus` — verifies create never autofills and targets title focus.
- `filtersTitlesCaseInsensitively` — verifies typed search narrows loaded destinations.

### Existing App Unit — `Noto2Tests/DigestSwipeTests.swift`

- `mapsEachDirectionToItsAction` — verifies right remains add-to and up remains create after removing the buttons.

## Implementation Details

- Own the picker mode, query, and title in one testable `DigestFileInputState`.
- Bind `.searchFocused` and `.focused` to explicit SwiftUI focus state and request the mode's focus target when the sheet appears or the picker mode changes.
- Load the vault tree in a detached task, then derive note/folder options on the main actor. Search filters the loaded candidates but remains editable during loading.
- Remove the Digest card's legacy action row and the obsolete suggested-title/clear-title behavior.

## Residual Risks

The complete focus and gesture-to-destination flow passed independent iPhone simulator verification in `.codex/evidence/20260904-192132-ios-visual-audit/`. The seeded vault loaded too quickly to preserve the loading row in evidence, but typing without a tap was verified and the scan now runs off-main by construction.

The independent audit is PARTIAL only for iPad visual coverage: it provisioned an isolated iPad mini simulator, but FlowDeck reported no running app after launch and repeatedly failed to parse its accessibility tree. No iPad-specific code path changed; the remaining risk is layout/runtime validation on iPad, not a known product failure.

## Bugs

- `bug-reports/032-noto2-digest-direct-input.md`
