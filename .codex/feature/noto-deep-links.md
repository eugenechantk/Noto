# Feature: Noto Deep Links

## User Story

Telegram Readwise digest notifications should include a Noto link that opens the corresponding capture note directly in the active Noto vault.

## User Flow

1. The Readwise auto-digest worker finds or creates a Noto capture and knows its vault-relative markdown path.
2. The worker sends a Telegram notification containing both the original source URL and a `noto://open?path=<vault-relative-path>` URL.
3. Opening that URL launches Noto if needed and routes the workspace to the matching vault document.
4. While Noto is already running, the same URL routes the current workspace to the matching document.

## Success Criteria

- `noto://open?path=<vault-relative-path>` URLs can be built for vault-relative markdown paths.
- Noto accepts only `noto` scheme URLs with `open` host/action and a safe decoded vault-relative path.
- Noto rejects missing paths, absolute paths, path traversal, empty components, and non-markdown paths.
- Noto registers the `noto` URL scheme.
- Cold-start and runtime URL handling feed valid document links into workspace navigation.
- Readwise auto-digest notifications preserve the source URL and append the Noto deep link for the capture path.

## Test Strategy

- Swift app-target unit tests cover deep-link parsing/building and workspace URL routing state.
- TypeScript unit tests cover worker Noto URL construction and Telegram formatting.
- Build/typecheck verifies app and worker wiring.

## Tests

- `NotoTests/NotoDeepLinkTests.swift`
  - build URL encodes vault-relative paths.
  - parse URL decodes valid paths.
  - reject invalid scheme/action/missing/absolute/traversal/empty/non-markdown paths.
  - app URL router stores valid pending document links and ignores invalid URLs.
- `test/telegram.test.ts`
  - notification message includes source and Noto links.
- `test/noto.test.ts`
  - builds encoded Noto deep links from capture vault-relative paths and rejects unsafe paths.
- `test/worker.test.ts`
  - processed digest notification includes the capture Noto URL.

## Implementation Details

- Add a small `NotoDeepLink` app-target helper for validation and URL construction.
- Keep URL routing state in a root-owned app coordinator so `.onOpenURL` and launch URL handlers share the same path.
- Let `VaultWorkspaceView` consume pending document links through its existing document-link routing path.
- Add worker-side Noto deep-link helper near existing Noto capture helpers and pass it into `formatDigestMessage`.
- Register `CFBundleURLTypes` through a partial app `Info.plist` merged with generated plist values. Exclude that file from the synchronized app folder's copied resources.
- Runtime smoke test opened `noto://open?path=Captures%2FThe%20State%20of%20Consumer%20AI%20-%20Usage.md` on an isolated iPhone simulator and verified the editor displayed the seeded capture.

## Residual Risks

- The simulator smoke test covered a warm running app plus iOS system confirmation. The earlier focused iOS test runner hung in `test-without-building`, so deterministic Swift tests were run on macOS and iOS coverage was verified by build, generated plist inspection, and runtime handoff.

## Bugs

- None yet.
