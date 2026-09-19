# Feature: Noto 2 Share Extension — link quick capture

## User Story

As a Noto 2 user, when I'm looking at a web page (or any app that shares a URL) I want to tap Share → Noto 2 and have that link filed as a quick capture, in the vault's markdown link format, with no further input — so the link lands in my inbox with the same one-gesture cost as the Capture tab.

## User Flow

1. In Safari (or any app), tap the Share button and pick **Noto 2** in the app row.
2. A **Link captured** sheet appears (dark, Noto styling): the link's title and host, "Saved to your inbox as a quick capture", a primary **Keep editing** button, and a circular ✕ close button in the header.
   - **Keep editing** opens Noto 2 straight into that capture note in the editor, ready to type.
   - **✕** (or swiping the sheet away) just closes it; the link is still captured and shows up in Digest next time Noto 2 is active.
3. The capture body is `[<page title>](<url>)`. If the share included selected text alongside the URL, it follows the link as a second paragraph. With no title available the link text is the URL itself (the same shape the editor's link toggle produces).
4. The next time Noto 2 is active (cold launch or return from background) it files every staged capture into `inbox/<YYYY-MM-DD>-<sha8>.md` through `CaptureFilingService`, exactly like the Capture tab. The date stamp is the moment the link was shared, not the moment the app drained it.
5. The capture then appears in Digest and is indexed for Search.

## Why the app drains instead of the extension writing to the vault

The vault is a user-picked iCloud Drive folder held through a security-scoped bookmark. iOS bookmarks are tied to the sandbox that created them; the share extension runs in its own sandbox and cannot resolve Noto 2's bookmark. The only container both sides can write is an **App Group** (`group.com.eugenechan.Noto2`). So the extension stages the capture there and Noto 2 files it on its next activation. This is the same shape Bear/Obsidian use for share-sheet captures.

## Success Criteria

1. **SC1 — link format.** Given a URL and a page title, the capture body is `[title](url)`; `[`/`]` and newlines in the title cannot break the markdown link and `(`/`)` in the URL are percent-encoded so `HyperlinkMarkdown` parses the result as one link.
2. **SC2 — payload resolution.** A share that carries an explicit URL uses it; a share that carries only text uses the first `http(s)` URL in the text; text that is not the URL is kept as a second paragraph; a share with no URL is rejected (nothing staged).
3. **SC3 — staging is durable and ordered.** The extension writes each capture as its own file in the App Group container; listing returns them oldest-first; removing one leaves the rest.
4. **SC4 — drain files through the existing capture path.** Each staged capture becomes `inbox/<date>-<sha8>.md` with the standard frontmatter, dated at share time, and the staged file is removed only after the vault write succeeded. A failed write leaves the staged capture in place for the next drain.
5. **SC5 — drain runs at the right moments.** Noto 2 drains when the vault becomes available at launch and on every return to `.active`, then schedules search indexing for each filed note.
6. **SC6 — the share sheet works end to end.** Sharing a page from Safari in the simulator shows the Noto 2 confirmation, and after foregrounding Noto 2 the link capture is visible in Digest.
7. **SC7 — Link captured sheet.** Tapping Noto 2 in the share sheet shows a sheet titled "Link captured" with the page title and host, an "Keep editing" button and a ✕ close button; it does not auto-dismiss.
8. **SC8 — Keep editing opens the note.** "Keep editing" launches Noto 2, which files that staged capture and opens the resulting inbox note in the editor (Browse tab), cold or warm. The deep link is `noto2://capture?shared=<UUID>`; a malformed or extra query item is not a route.
9. **SC9 — Close keeps the capture.** ✕ dismisses the sheet without opening Noto 2; the capture remains staged and is filed on Noto 2's next activation.

## Test Strategy

- SC1–SC3 are pure Foundation logic → package `Packages/NotoShareCapture`, `swift test`.
- SC4 composes the package with `CaptureFilingService` (lives in `NotoShared/`) → app-level Swift Testing in `Noto2Tests`, real temp directories, no mocks.
- SC5 is SwiftUI wiring in `RootTabView` — not provable with Swift Testing; covered by the simulator audit.
- SC6 is simulator-only (share sheet + extension process) → independent visual evidence audit.

## Tests

### Package Unit — `Packages/NotoShareCapture/Tests/NotoShareCaptureTests/SharedLinkCaptureTests.swift`
- `bodyIsMarkdownLinkWithTitle` — SC1
- `bodyFallsBackToURLAsTitle` — SC1
- `titleBracketsAndNewlinesAreNeutralised` — SC1
- `parenthesesInURLArePercentEncoded` — SC1
- `sharedTextFollowsLinkAsSecondParagraph` — SC2
- `textEqualToURLOrTitleIsNotRepeated` — SC2

### Package Unit — `.../SharedLinkPayloadTests.swift`
- `explicitURLWins` — SC2
- `urlIsExtractedFromTextWhenNoAttachment` — SC2
- `payloadWithoutURLResolvesToNil` — SC2
- `pageTitleFromPreprocessingIsPreferredOverItemTitle` — SC2

### Package Integration — `.../PendingCaptureStoreTests.swift`
- `enqueueWritesOneFilePerCapture` — SC3
- `pendingReturnsOldestFirst` — SC3
- `removeDeletesOnlyThatCapture` — SC3
- `corruptFilesAreSkippedNotFatal` — SC3

### App Unit — `Noto2Tests/Noto2QuickCaptureRoutingTests.swift`
- `sharedCaptureURLRoundTrips` — SC8
- `sharedCaptureURLsWithBadIDsOrExtraItemsAreRejected` — SC8
- `routerCarriesTheSharedCaptureIDUntilCleared` — SC8

### App Integration — `Noto2Tests/SharedCaptureDrainTests.swift`
- `drainFilesEachCaptureIntoInboxAndClearsStaging` — SC4, SC8 (each filed result is paired with its staged capture id)
- `drainStampsFileWithShareDateNotDrainDate` — SC4
- `failedWriteLeavesCaptureStaged` — SC4
- `drainWithEmptyStoreIsNoOp` — SC4

## Implementation Details

- **Package `NotoShareCapture`** (Foundation only, no UIKit):
  - `SharedLinkCapture.body(url:title:text:)` — the formatter (SC1/SC2).
  - `SharedLinkPayload` — value type holding what the item providers yielded (`urls`, `texts`, `pageTitle`) with `resolve()` → `(url, title, text)`.
  - `PendingCaptureStore` — App Group staging. One JSON file per capture (`<unix-ms>-<uuid>.json` → `PendingCapture {id, body, createdAt}`), `enqueue`, `pending()`, `remove(id:)`. Container URL is injected; `PendingCaptureStore.appGroup(_:)` resolves the shared container.
- **`NotoShared/Storage/SharedCaptureDrain.swift`** — `drain()` iterates `pending()`, files each via `CaptureFilingService` with `now` pinned to `createdAt`, removes on success, returns the filed results for indexing.
- **`Noto2/RootTabView.swift`** — calls the drain in `.task(id: vaultURL)` and on `scenePhase == .active`, then `SearchIndexController.shared.scheduleRefreshFile` per filed note, and posts `SharedCaptureDrain.didFileNotification` so `DigestScreen` refreshes if it is on screen.
- **Target `Noto2ShareExtension`** (`com.eugenechan.Noto2.ShareExtension`): `ShareViewController` loads `public.url` / `public.plain-text` / the JS preprocessing result, resolves the payload, enqueues, then hosts the SwiftUI `LinkCapturedSheet` directly in its view (iOS already presents the extension inside a sheet container; a nested sheet floated over a blank light card). ✕ → `completeRequest`. **Keep editing** → `noto2://capture?shared=<id>` opened through the responder chain: `extensionContext.open` returns false for share extensions and UIKit refuses the legacy `openURL:` ("needs to migrate…"), so the code walks to the `UIApplication` responder and calls `open(_:options:completionHandler:)` through its IMP with a real completion block. `UIWindowScene` also answers that selector but forwards it into a `doesNotRecognizeSelector` crash, so scenes are skipped.
- **Route + ledger**: `Noto2LaunchRoute.route(for:)` (in `Noto2ControlShared/`, compiled into app, widget and extension) parses the strict URL; `Noto2LaunchRouter.requestedSharedCaptureID` carries the id; `RootTabView` drains, records `sharedCaptureNotes[id] = fileURL` from `SharedCaptureDrain.Outcome.filed` (now `FiledCapture` pairs), and opens the note via the existing `openFiledNote` path. Unknown id (filed by an earlier launch) falls back to the Digest tab. `NotoShareTitle.js` returns `document.title` + `document.URL` for Safari. Entitlements: App Group. Embedded by Noto 2 like the widget; `fastlane/.env.noto2` lists it in `EXTENSION_TARGETS`.
- **Entitlements**: `Noto2/Noto2.entitlements` gains the App Group. Device builds need the App Group capability enabled on all three App IDs before `bootstrap_match` regenerates profiles.

## Verification

- `Packages/NotoShareCapture`: `swift test` — 16/16 pass.
- `Noto2Tests` full suite on the isolated simulator (`flowdeck test -s Noto2`): 89/89 pass, including the 5 `SharedCaptureDrainTests`.
- `Noto-iOS` scheme builds (the drain compiles into Noto too, since `NotoShared/` is shared).
- `Noto2Tests` re-run after the sheet/deep-link change: 92/92 pass (3 new routing tests).
- Manual, sheet flow (2026-09-19): share Haskell page → "Link captured" sheet → **Keep editing** → extension log `open(_:options:completionHandler:) via UIApplication … success=true` → app log `Opening shared capture 43FD168B… at 2026-09-19-1e2d8aee.md` → editor shows the note with the rendered link. ✕ path: sheet closes, capture stays staged.
- Manual end-to-end, v1 (pill) on `cc-012emy8m` (iPhone 17 Pro, iOS 26.3): Safari → More → Share → "Noto 2" staged `[Swift (programming language) - Wikipedia](https://en.wikipedia.org/wiki/Swift_%28programming_language%29)` in the App Group; foregrounding Noto 2 produced `inbox/2026-09-18-6f53aba1.md` with `created:` at the share time and the Digest tab showed the card.
- Independent visual audit: **PASS** — see `## Evidence`.

## Evidence

`.codex/evidence/20260918-235728-ios-visual-audit/evidence.md` (auditor shared a different page, Rust_(programming_language), to keep it independent):

- `04-share-sheet-noto2-row.png` — "Noto 2" in the share sheet app row (SC6).
- `05d-session-t+0.1s-pill.jpg`, `05e-session-t+1.45s.jpg` — confirmation pill ~110 ms after staging, sheet gone by +1.45 s with no input (SC6).
- `06-staged-capture.json` — `[Rust (programming language) - Wikipedia](https://en.wikipedia.org/wiki/Rust_%28programming_language%29)` in the App Group (SC1, SC3).
- `10-drain-proof.txt`, `10-inbox-2026-09-19-c941a054.md` — staging emptied, inbox note `created:` equals the share time (SC4, SC5).
- `09-digest-tab.png` — Digest shows "2 to process" with the Rust link card on top (SC6).

`.codex/evidence/20260919-003252-ios-visual-audit/evidence.md` — sheet version, SC7 ✔ SC9 ✔, SC8 FAIL with a note already open in Browse (see `## Bugs`).

`.codex/evidence/20260919-010500-ios-visual-audit/evidence.md` — re-audit after the fix, **PASS**: SC8 with Meeting Notes open (Kotlin), with Shopping List open (Lua), and cold launch (Perl, fresh pid, staging cleared, inbox file dated at share time, editor on the Browse stack).

Success criteria: SC1 ✔ SC2 ✔ SC3 ✔ SC4 ✔ SC5 ✔ SC6 ✔ SC7 ✔ SC8 ✔ SC9 ✔

## Residual Risks

- **Device signing not exercised.** Simulator builds embed the App Group only in the simulated entitlements. A device/TestFlight build needs the App Group capability enabled on `com.eugenechan.Noto2`, `.QuickCaptureControl` and `.ShareExtension` in the developer portal, then `fastlane ios bootstrap_match` (with `.env.noto2`) to mint the new `match AppStore com.eugenechan.Noto2.ShareExtension` profile. Until then a device build of Noto 2 will fail signing.
- **macOS Noto scheme is already broken on `main`, independently of this change.** `flowdeck build -s Noto-macOS -D "My Mac"` (with `CODE_SIGNING_ALLOWED=NO`) fails on one pre-existing error: `NotoShared/Views/EditorContentView.swift:23` uses the iOS-only `EditorKeyboardToolbarStyle` outside `#if os(iOS)` (since commit `af25747`). That is the only error in the log, so `SharedCaptureDrain` and the new package do compile for macOS.
- **Non-Safari share sources** (YouTube, X, Messages) only carry `public.url`/text, no page title, so the link text is the URL itself. This is by design (matches the editor's bare-URL toggle) but untested on device.
- **Drain is app-activation driven.** A shared link sits in the App Group until Noto 2 is next opened; there is no background filing.
- **Opening the app from the extension relies on a private path.** Calling `UIApplication.open(_:options:completionHandler:)` through the responder chain is the de-facto standard (no public API exists) and is what ships in many App Store apps, but Apple could close it in a future iOS. If it ever fails, the sheet still completes and the capture is still filed on the next launch — only the shortcut degrades.
- **Note title shows raw markdown.** The editor's nav title for a link-only note is the first line verbatim (`[Haskell - Wikipedia](https://…)`). Pre-existing title derivation; a follow-up could strip link syntax for titles.

## Bugs

- **"Keep editing" did not switch the editor when a note was already open in Browse** (found by the independent audit, `.codex/evidence/20260919-003252-ios-visual-audit/`, reproduced 2/2). `BrowseScreen.consumePendingNote` replaces the stack with `[note]`; when a note was already pushed, the new value landed in the same stack position and SwiftUI reused the existing `NoteScreen`, whose `@State` session had been built from the old note. Fix: `.id(destination)` on the `navigationDestination` view so a different note at the same position gets its own screen. Verified manually (Meeting Notes open → share Elixir → Add notes → editor shows Elixir) and re-audited.
