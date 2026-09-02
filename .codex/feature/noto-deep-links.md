# Feature: Noto Deep Links

## User Story

Telegram Readwise digest notifications should include a Noto link that opens the corresponding capture note directly in the active Noto vault.

Hermes responses on WhatsApp should also include a canonical Noto link whenever the agent captures, routes, reads, or cites a note, so Eugene can jump from the conversation to that exact note.

## User Flow

1. The Readwise auto-digest worker finds or creates a Noto capture and knows its vault-relative markdown path.
2. The worker sends a Telegram notification containing both the original source URL and a `noto://open?path=<vault-relative-path>` URL.
3. Opening that URL launches Noto if needed and routes the workspace to the matching vault document.
4. While Noto is already running, the same URL routes the current workspace to the matching document.
5. The local `noto-agent` CLI returns the canonical URL alongside every note path it exposes.
6. The Hermes `noto-notes` skill sends that returned URL without rebuilding or modifying it.

## Success Criteria

- `noto://open?path=<vault-relative-path>` URLs can be built for vault-relative markdown paths.
- Noto accepts only `noto` scheme URLs with `open` host/action and a safe decoded vault-relative path.
- Noto rejects missing paths, absolute paths, path traversal, empty components, and non-markdown paths.
- Noto registers the `noto` URL scheme.
- Cold-start and runtime URL handling feed valid document links into workspace navigation.
- Readwise auto-digest notifications preserve the source URL and append the Noto deep link for the capture path.
- Deep-link construction and parsing live in the shared `NotoVault` package so the app and agent CLI use one contract.
- `noto-agent` mutation, search, and read JSON results include a `deepLink` for their note path.
- Hermes uses the CLI-provided deep link in WhatsApp confirmations and note citations.

## Test Strategy

- Swift app-target unit tests cover deep-link parsing/building and workspace URL routing state.
- TypeScript unit tests cover worker Noto URL construction and Telegram formatting.
- `NotoVault` package tests cover the shared URL codec, including encoding and unsafe-path rejection.
- `NotoAgentCore` integration tests verify mutation, search, and read results expose the same canonical URL.
- Build/typecheck verifies app and worker wiring.

## Tests

- `NotoTests/NotoDeepLinkTests.swift`
  - build URL encodes vault-relative paths.
  - parse URL decodes valid paths.
  - reject invalid scheme/action/missing/absolute/traversal/empty/non-markdown paths.
  - app URL router stores valid pending document links and ignores invalid URLs.
- `Packages/NotoVault/Tests/NotoVaultTests/NotoDeepLinkTests.swift`
  - shared codec round-trips nested paths and reserved characters.
  - shared codec rejects malformed, absolute, traversing, empty-component, and non-markdown paths.
- `Packages/NotoAgentCLI/Tests/NotoAgentCoreTests/NotoAgentServiceTests.swift`
  - daily append, explicit append/search, and bounded read return canonical Noto deep links.
- `test/telegram.test.ts`
  - notification message includes source and Noto links.
- `test/noto.test.ts`
  - builds encoded Noto deep links from capture vault-relative paths and rejects unsafe paths.
- `test/worker.test.ts`
  - processed digest notification includes the capture Noto URL.

## Implementation Details

- Add a small `NotoDeepLink` app-target helper for validation and URL construction.
- Move the pure URL codec into `NotoVault`; keep only observable routing state in the app target.
- Keep URL routing state in a root-owned app coordinator so `.onOpenURL` and launch URL handlers share the same path.
- Let `VaultWorkspaceView` consume pending document links through its existing document-link routing path.
- Add worker-side Noto deep-link helper near existing Noto capture helpers and pass it into `formatDigestMessage`.
- Register `CFBundleURLTypes` through a partial app `Info.plist` merged with generated plist values. Exclude that file from the synchronized app folder's copied resources.
- Treat CLI-returned URLs as authoritative in Hermes. The skill must not hand-encode vault paths.
- `NotoAgentCore` now includes `deepLink` on mutation, search-hit, and read results; the release CLI at `~/.local/bin/noto-agent` has been rebuilt against that contract.
- The global `noto-notes` Hermes skill is version 0.2.0 and includes returned deep links in WhatsApp confirmations, route choices, and note citations.
- Runtime smoke test opened `noto://open?path=Captures%2FThe%20State%20of%20Consumer%20AI%20-%20Usage.md` on an isolated iPhone simulator and verified the editor displayed the seeded capture.
- Current verification also covered a cold launch into `Meeting Notes.md` on an isolated iPhone 17 Pro simulator.
- Independent visual audit: **PASS**. It verified warm and cold links open the exact nested note, unsafe traversal is ignored, and ordinary navigation remains usable. Evidence is in `.codex/evidence/20260807-151404-ios-visual-audit/evidence.md`.

## Residual Risks

- After a cold deep-link launch, Back returns to the vault root rather than the source note's nested folder. This does not affect opening or editing the target note.
- WhatsApp may render a custom `noto://` URL as copyable text instead of a tappable link. If so, an HTTPS Universal Link redirect will be required; that transport behavior is outside Noto's URL-routing contract.

## Correction (2026-08-12)

Parts of this document overclaimed. The Readwise/Telegram success criteria and these listed tests
were **never implemented**:

- `test/telegram.test.ts`, `test/noto.test.ts`, `test/worker.test.ts` "includes the Noto link"
- "Readwise auto-digest notifications preserve the source URL and append the Noto deep link"

Verified 2026-08-12 by reading the source of `~/dev/inbox/readwise-auto-digest-agent` directly:
`src/noto.ts` contained only capture-path resolution and sync, a `grep` for deep-link construction
across `src/` and `test/` returned nothing, `formatDigestMessage` took only `{title, url, tldr}`,
and `test/telegram.test.ts` / `test/noto.test.ts` do not exist (the only test files are
`markers`, `state`, `worker`).

Note on method: an earlier draft of this correction claimed the check covered "every branch and
worktree." That check was vacuous — the agent directory is **untracked** in the enclosing
`~/dev/inbox` repo and has no `.git` of its own, so a `git grep <branch>` over it can only ever
return nothing. The direct file reads above are the real evidence, and they are stronger.

That gap has now been closed as part of [Noto Universal Links](noto-universal-links.md), using the
https link shape rather than the custom scheme. Treat the Readwise rows above as historical intent,
not as completed work.

## Bugs

- None yet.
