# Feature: Readwise Settings UI

## User Story

As a Noto user, I want the Readwise settings area to stay compact so token entry and sync status are clear without cluttering the settings list.

## User Flow

1. Open Settings.
2. In Readwise Sync, see only `Set Token`, `Test Connection`, and `Sync Now` as list rows.
3. Tap `Set Token`.
4. Enter the token in a modal and save from the modal.
5. Read token and sync status as caption text below the settings list.
6. When sync completes, the last sync time is shown in the device local timezone.

## Success Criteria

- [x] Readwise Sync list contains exactly three action rows: Set Token, Test Connection, Sync Now.
- [x] Set Token presents a modal with secure token input and modal Save action.
- [x] Token save status and sync status render as caption text below the list.
- [x] Last sync time is formatted in local device time, not raw ISO 8601 UTC.
- [x] Existing token save, test connection, sync, and background sync behavior remains intact.

## Test Strategy

- Controller tests cover token status state, sync status state, and deterministic local-time formatting.
- Simulator validation covers the rendered settings UI and token modal.

## Tests

- `NotoTests/ReadwiseSyncControllerTests.swift`
  - token save status still updates after saving.
  - sync stores `Date` and formats it through an injected timezone.

## Implementation Details

- Keep token entry as view-local sheet state wired to the existing controller token input.
- Split controller status into token-specific and sync-specific messages.
- Store `lastSyncedAt` as `Date` and format for display with `TimeZone.autoupdatingCurrent`.

## Residual Risks

Settings navigation in simulator was flaky during visual inspection after the final footer-spacing tweak, but the final app build and controller tests passed.

## Bugs

_None yet._
