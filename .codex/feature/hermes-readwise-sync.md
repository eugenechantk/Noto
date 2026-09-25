# Feature: Hermes Readwise Sync

## User Story

As a Noto 2 user, I want the always-on Hermes service on the MacBook Pro to keep my shared Noto vault synchronized with Readwise and Reader, so imports do not depend on opening the original Noto app.

## User Flow

1. Hermes runs its existing Readwise scheduled job every 15 minutes.
2. The job invokes Noto's shared incremental sync engine before digest processing.
3. Reader documents and Readwise highlights are created or refreshed in the shared iCloud vault.
4. The existing digest worker then summarizes newly changed Reader documents and sends its normal notification.

## Success Criteria

- [x] SC1: The CLI exposes one command mode that runs the same incremental Reader + Readwise sync engine used by the original Noto app.
- [x] SC2: Incremental sync persists and reuses the vault's existing Readwise sync checkpoint.
- [x] SC3: Hermes runs full incremental sync before its existing digest worker every 15 minutes.
- [x] SC4: A failed full sync fails the scheduled job visibly and does not run the digest against stale data.
- [x] SC5: Credentials remain outside command-line arguments and committed files.

## Test Strategy

- Package tests verify CLI option selection and the incremental-mode contract without network access.
- Existing sync-engine integration tests verify checkpoint persistence and Reader + Readwise orchestration.
- A live Hermes run verifies the installed script, credentials, vault path, network access, and scheduler integration.

## Tests

### Package integration

- `ReadwiseSyncTests.incrementalSyncUsesSavedTimestampsAndJoinsKnownReaderHighlights` — verifies SC1 and SC2 with real state persistence, Reader note refresh, highlight joining, and a separate Readwise source.
- `ReadwiseSyncTests.incrementalSyncDoesNotDeleteReaderNoteWhenReaderReturnsNoDocuments` — verifies the scheduled incremental path is safe when a polling window returns no Reader documents.

### CLI and live integration

- CLI help and invalid-mode invocations verify the new command contract and credential-free argument handling for SC1 and SC5.
- A manually triggered Hermes job verifies SC3–SC5 against the configured live vault and scheduler.

## Implementation Details

- `noto-readwise-sync --incremental` calls `SourceLibrarySyncEngine.syncIncrementally`, the same package API used by the original Noto app.
- `--limit`, `--source-dir`, `--include-deleted` / `--no-include-deleted`, and `--dry-run` remain available in incremental mode.
- Explicit one-source modes and checkpoint-managed incremental mode are mutually exclusive.
- Hermes script `~/.hermes/scripts/readwise_auto_digest.sh` reads the token and vault path from its existing local `.env`, passes the token only through the process environment, and aborts before digest processing if full sync fails.
- The first live run advanced both vault checkpoints to `2026-09-22T17:10:59Z`, created one new Reader capture, processed its digest, and left the scheduler active for the next 15-minute interval.

## Residual Risks

- The original Noto app can still initiate the same idempotent sync when opened; the Hermes lock prevents overlapping Hermes runs but cannot lock an app-initiated sync across processes.
- Hermes depends on the Pro being awake, logged into Eugene's GUI session, online, and able to access the locally materialized iCloud vault.
- No simulator validation was run because this feature has no UI behavior.

## Bugs

None yet.
