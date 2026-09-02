# Feature: Noto Universal Links

## User Story

Eugene receives Noto note links inside messaging apps (WhatsApp, Telegram, Slack) and in
email. Today those links use the custom `noto://open?path=…` scheme, which most messengers
refuse to autolink — the link renders as dead grey text he has to copy and paste.

He wants an `https://` link that is tappable everywhere and opens the exact note in Noto on
iOS, iPadOS and macOS, without a browser hop when possible.

## User Flow

1. `noto-agent` (or the Readwise digest worker) produces a canonical link for a
   vault-relative markdown path.
2. The link is `https://noto.eugenechantk.me/open#path=<percent-encoded-vault-relative-path>`.
3. Messengers autolink it because it is `https`.
4. Tapping it on a device with Noto installed opens Noto directly via Universal Links
   (no browser). The router receives the URL and navigates to the note.
5. If the tap happens inside an in-app browser that does not honour Universal Links (WhatsApp's
   WKWebView is the known case), the static fallback page loads and shows an "Open in Noto"
   button. Tapping the button fires `noto://open?path=…` from a user gesture, which always works.
6. If Noto is not installed, the page explains what the link is instead of erroring.

## Success Criteria

- **SC1** — `NotoDeepLink.webURL(vaultRelativePath:)` builds
  `https://noto.eugenechantk.me/open#path=<encoded>` for valid vault-relative markdown paths and
  returns `nil` for unsafe ones (absolute, traversal, empty component, non-markdown).
- **SC2** — `NotoDeepLink.vaultRelativePath(from:)` accepts the https form (fragment-encoded),
  and still accepts the existing `noto://open?path=` form. Both round-trip.
- **SC3** — The https form is rejected for a wrong host, wrong path, wrong scheme, or an unsafe
  decoded path, exactly as the custom-scheme form is.
- **SC4** — `https://noto.eugenechantk.me/.well-known/apple-app-site-association` serves the AASA
  for appID `39GJBP8V5A.com.eugenechan.Noto` over https, `content-type: application/json`, HTTP 200,
  no redirect.
- **SC5** — The Noto app declares `com.apple.developer.associated-domains` =
  `applinks:noto.eugenechantk.me` and routes an incoming universal link through the same
  `NotoDeepLinkRouter` path as the custom scheme, both warm and cold.
- **SC6** — `https://noto.eugenechantk.me/open#path=…` opened on a simulator with Noto installed
  opens the correct note.
- **SC7** — The fallback page, loaded in a browser, decodes the fragment and its button targets the
  correct `noto://` URL. It never sends the note path to the server.
- **SC8** — `noto-agent` mutation, search-hit, and read results return the https link as `deepLink`.

## Test Strategy

Package Swift tests own the URL codec (pure, platform-neutral — SC1, SC2, SC3). App-target Swift
tests own router behaviour for the new URL shape (SC5, state only). `NotoAgentCore` integration
tests own the CLI contract (SC8). Live HTTP probes prove the deployed AASA and headers (SC4).
Simulator validation proves real universal-link routing and the fallback page (SC6, SC7).

## Tests

### Package unit — `Packages/NotoVault/Tests/NotoVaultTests/NotoWebDeepLinkTests.swift`
- `buildsFragmentEncodedWebURL` — SC1
- `roundTripsNestedWebPath`, `roundTripsUnicodeAndReservedCharacters` — SC1, SC2
- `parsesQueryFormForRobustness`, `parsesTrailingSlashAndUppercaseHost` — SC2
- `stillParsesCustomSchemeURLs` — SC2 (no regression on the existing contract)
- `rejectsUnsafeOrForeignWebURLs`, `refusesToBuildWebURLsForUnsafePaths` — SC3
- `webURLNeverLeaksPathIntoServerVisibleComponents` — SC7 (privacy invariant)

### App target — `NotoTests/NotoDeepLinkTests.swift`
- `routerAcceptsUniversalLinkURLs` — SC5
- `routerIgnoresForeignOrUnsafeUniversalLinks` — SC5, SC3
- `universalLinkHostMatchesEntitlementDomain` — pins the host against entitlement drift

### Package integration — `Packages/NotoAgentCLI/Tests/NotoAgentCoreTests/NotoAgentServiceTests.swift`
- daily append / append+search / read now assert the https `deepLink` — SC8

### Live probes (SC4) and simulator validation (SC6) — see Verification Evidence below.

## Verification Evidence

Run 2026-08-11.

| Criterion | Result | Evidence |
|---|---|---|
| SC1–SC3 | PASS | `swift test` in `Packages/NotoVault` — 90/90 across 14 suites |
| SC8 | PASS | `swift test` in `Packages/NotoAgentCLI` — 5/5 |
| SC4 | PASS | `curl` → `HTTP/2 200`, `content-type: application/json`, no redirect, correct appID body |
| SC5 (declaration) | PASS | Built app's `Noto.app-Simulated.xcent` contains `com.apple.developer.associated-domains = [applinks:noto.eugenechantk.me]` |
| SC5 (routing) | PASS | App-target router tests + live warm/cold routing below |
| SC6 warm | PASS | App running at vault root → universal link → opened `Captures/The State of Consumer AI - Usage.md` directly, no Safari hop |
| SC6 cold | PASS | App terminated → universal link → launched and opened `Meeting Notes.md` |
| SC7 | PASS | Fallback page decoded the fragment, button `href` byte-identical to `NotoDeepLink.openURL` output; traversal payload `..%2FSecrets.md` rendered "Nothing to open" |

Simulator: `cc-2955b8de` (`0F07D332-586D-4F5D-9CE9-0CEB15B37C2F`), iOS 26.3, vault seeded via `.maestro/seed-vault.sh`.

App-target suite: `NotoDeepLinkTests` 8/8 pass (5 existing + 3 new). Full `Noto-iOS` plan: 297/311
pass, 14 fail. Every failing suite (`TextKit2MarkdownLayoutTests`, `TextKit2EditorLifecycleTests`,
`TagControllerTests`, `SearchIndexControllerTests`, `OwnershipRearchitecturePhase0BaselineTests`)
maps to editor/tag files already modified or untracked before this session. The only shared code this
change touches is `NotoDeepLink.swift`, whose entire pre-existing test suite still passes. No
baseline run was performed, so "pre-existing" is inferred from disjoint domains, not proven.

The installed CLI (`~/.local/bin/noto-agent` → release build) was rebuilt and executed against a
probe vault: `read`, `search`, `append`, and `daily-append` all return the https form.

### Readwise digest agent (`~/dev/inbox/readwise-auto-digest-agent`)

The previous feature doc claimed this already appended Noto links. It did not — verified by reading
the source directly (see the correction note in `noto-deep-links.md`). Added rather than updated:

> **This directory is not under version control.** It is untracked inside `~/dev/inbox` and has no
> `.git` of its own, so the changes below — and everything that preceded them — have no history and
> no backup.

- `src/notoLink.ts` — `notoNoteUrl()`, a deliberate mirror of `NotoDeepLink.webURL` (same validation
  rules, same percent-encoding set including `!'()*` so parentheses can't terminate Telegram's
  Markdown link span).
- `formatDigestMessage` gained an optional `notoUrl`, appended as `[Open in Noto](…)` below the TL;DR,
  omitted entirely when the capture path can't be resolved.
- `src/worker.ts` passes `notoNoteUrl(relPath)` — `relPath` was already resolved for the capture write.

Verification: `pnpm typecheck` clean, `pnpm test` 32/32. Cross-language parity is not asserted from
reasoning — the 10 expected encodings in `test/notoLink.test.ts` were generated by running the real
Swift codec through `noto-agent read` and compared literally. The worker-wiring assertion was
mutation-tested (setting `notoUrl: null` fails it) so it cannot pass vacuously.

The Hermes `noto-notes` skill needed no logic change (it treats CLI links as authoritative), but its
two illustrative `noto://` examples were updated to the https form so they cannot bias the model
into "correcting" a real link back to the custom scheme.

### Bug found and fixed during verification

The fallback page rendered only on document load, so a fragment-only navigation (opening a second
link in an already-open tab) left the previous note on screen **with the button still pointing at
it** — it would have opened the wrong note. Fixed by extracting `render()` and binding it to
`hashchange`. Re-verified: page moved from "Nothing to open" to the new note without a reload.

## Implementation Details

- Host: `noto.eugenechantk.me`, a dedicated Cloudflare Pages project. Chosen over the apex so the
  existing pages-router Worker on `eugenechantk.me/pages/*` is never in the request path for AASA.
- Path carried in the **fragment**, not the query: fragments are never sent to the server, so note
  titles stay out of Cloudflare access logs and out of link-preview fetches by messengers. The app
  still receives the full URL including the fragment. The query form is accepted on parse for
  robustness but never generated.
- appID = `<team>.<bundle>` = `39GJBP8V5A.com.eugenechan.Noto` (one target serves iOS + macOS).

## Residual Risks

- **Physical devices need a provisioning profile refresh.** Simulator builds don't enforce
  capability entitlements, so the simulator proof above does not prove device behaviour. Before the
  next device/TestFlight build, the App ID `com.eugenechan.Noto` needs the Associated Domains
  capability enabled in the developer portal and the match AppStore profile regenerated. Until
  then, universal links work on simulator but not on Eugene's iPhone/iPad, and a device build may
  fail to sign with the new entitlement.
- **macOS is unverified.** The entitlement is shared by the single target, but no macOS run was
  performed. The routing path is the same `NotoDeepLinkRouter`, so risk is low but non-zero — the
  cold-launch path on macOS goes through `WindowGroup(for: String.self)`, which differs from iOS.
- **WhatsApp's in-app browser is unverified against the real app.** The fallback page is proven to
  produce the correct `noto://` href, and a user-gesture scheme jump is the documented-reliable
  path, but the actual WhatsApp → Noto hop has not been exercised end to end.
- **Links already sent using `noto://` keep working** — the parser still accepts that form — but
  anything the CLI emits from now on is https, so old and new links coexist.
- The AASA is cached by iOS after install. Changing the applinks components later requires an app
  reinstall (or `?mode=developer`) to take effect on an existing install.

## Bugs

- Fixed during verification: fallback page ignored `hashchange`, so a second link opened in the same
  tab showed the previous note and its button targeted the wrong note. See Verification Evidence.
