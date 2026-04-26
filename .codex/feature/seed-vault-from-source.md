# Feature: Seed Simulator Vault From Source Vault

## User Story

As Eugene, I want the simulator seed script to copy my current Noto vault so search and UI testing can use realistic note data before the full-text search feature is implemented.

## User Flow

1. Build and install Noto on an isolated simulator.
2. Run `.maestro/seed-vault.sh <simulator-udid> --current-vault`.
3. The script replaces the simulator's local `Documents/Noto` vault with a copy of the current iCloud vault.
4. The app launches directly into the seeded vault.

## Success Criteria

- [x] Existing generated seed modes still support `small` and `large`.
- [x] `--current-vault` copies from `/Users/eugenechan/Library/Mobile Documents/com~apple~CloudDocs/Noto`.
- [x] `--source-vault <path>` copies from an arbitrary source vault.
- [x] Source-vault mode excludes disposable search index files.
- [x] Invalid source paths fail with a clear error.

## Test Strategy

Shell syntax and option parsing are verified without requiring a booted simulator. Full simulator behavior remains covered by existing Maestro/FlowDeck workflows when used for UI validation.

## Tests

- `bash -n .maestro/seed-vault.sh`
- `.maestro/seed-vault.sh --help`
- `.maestro/seed-vault.sh FAKE-UDID --source-vault /tmp/does-not-exist-for-noto-seed-test`

## Implementation Details

The script now has three seed modes:

- generated small vault
- generated large vault
- copied source vault

Copy mode uses `rsync` and excludes `.noto/search.sqlite*` plus `.DS_Store`.

## Residual Risks

This change was not run against a live simulator in this turn because the request was to add the seed option before search implementation. Live simulator seeding still depends on the app being installed and the simulator UDID being valid.

## Bugs

None yet.
