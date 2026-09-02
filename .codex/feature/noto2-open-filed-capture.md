# Feature: Open a filed quick capture from the status line

**Tier:** Product (Noto 2 ships to TestFlight).

## User Story

As someone capturing a thought in Noto 2, when I swipe the card to file it I want to tap the
confirmation line at the top of the Capture screen to open that note in the editor, so I can
immediately expand or correct what I just dashed off without hunting for it in Browse.

## User Flow

1. Type a thought on the Capture card.
2. Swipe right/up to file it. The card flies off and the status line reads
   `Filed · inbox/2026-09-01-1a2b3c4d.md`.
3. Tap that status line.
4. The app switches to Browse and pushes the editor for exactly that note.
5. Back returns to the Browse root.

## Design decisions

**Route into the Browse tab rather than presenting a sheet from Capture.** Capture is
deliberately decoupled from the vault workspace so cold launch stays fast
(`Noto2StartupPolicy.requiresWorkspace` — see `.codex/performance/20260826-noto2-cold-launch.md`).
Giving `CaptureScreen` a `VaultController` to present its own editor would undo that. Routing
through `RootTabView`, which already owns the controller and tab selection, reuses
`BrowseDestination.note` and the real `NoteScreen` lifecycle with no duplicated editor wiring.
Cost: the back button lands on the Browse root, not back on Capture. Accepted — the note is
now findable where it lives.

**The status line has to dwell longer to be tappable.** It currently auto-hides after 1.5s,
which is not a usable tap target. Filed lines (tappable) dwell 6s; discard lines keep 1.5s
since there is nothing to open.

**Resolution is shared with Search.** `SearchScreen.open(_:)` already turns a file URL into a
`BrowseDestination`. That logic moves to `BrowseDestination.note(at:in:)` and both callers use
it, so the two entry points cannot drift.

## Success Criteria

- **SC1** — Filing a capture produces a status line that carries the filed note's file URL.
- **SC2** — A discarded capture produces a status line with no file URL (nothing to open).
- **SC3** — An "already filed" (duplicate) capture is still tappable and points at the
  existing note.
- **SC4** — A tappable status line dwells long enough to be tapped (6s); a non-tappable one
  keeps the short 1.5s dwell.
- **SC5** — A filed note's file URL resolves to the `BrowseDestination.note` for that exact
  note, including notes in subfolders such as `inbox/`.
- **SC6** — A file URL outside the vault, or one with no note behind it, resolves to `nil`
  rather than navigating somewhere wrong.
- **SC7** — Tapping the status line opens that note's editor with its captured text.

## Test Strategy

SC1–SC4 are pure value-type behaviour on `CaptureStatus`, extracted out of the view so it can
be tested directly. SC5–SC6 are integration tests over a real temp vault through
`VaultController`. SC7 is navigation wiring — Swift Testing cannot prove it, so it is the
simulator/visual-audit criterion.

## Tests

### Unit
- `Noto2Tests/CaptureStatusTests.swift`
  - `filedStatusCarriesTheFileURL` — SC1
  - `discardedStatusHasNoFileURL` — SC2
  - `duplicateStatusIsStillOpenable` — SC3
  - `openableStatusDwellsLongerThanADiscard` — SC4
  - `filedTextNamesTheRelativePath` — SC1

### Integration
- `Noto2Tests/CaptureStatusTests.swift` (real temp vault via `VaultController`)
  - `filedNoteURLResolvesToItsDestination` — SC5
  - `noteInSubfolderResolvesToItsOwnDirectory` — SC5
  - `urlOutsideTheVaultResolvesToNil` — SC6
  - `urlWithNoNoteBehindItResolvesToNil` — SC6

## Implementation Details

- `Noto2/Capture/CaptureStatus.swift` (new) — the status line as a testable value:
  `glyph`, `text`, `fileURL`, `isDiscard`, `dwell`; factories `filed(...)` / `discarded()`.
- `Noto2/Capture/CaptureScreen.swift` — `StatusLine` replaced by `CaptureStatus`; the status
  slot becomes a `Button` when `fileURL != nil`; calls `onOpenFiledNote`.
- `Noto2/Browse/BrowseScreen.swift` — `BrowseDestination.note(at:in:)`; `BrowseScreen` accepts
  a `pendingNoteURL` binding and pushes it.
- `Noto2/RootTabView.swift` — owns `pendingNoteURL`, starts deferred services on demand, and
  switches to Browse.
- `Noto2/Search/SearchScreen.swift` — `open(_:)` now uses the shared resolver.

## Verification

**Swift Testing:** `flowdeck test -s Noto2` → 54/54 pass (9 new). `Packages/NotoSearch`
→ 129 tests; one intermittent failure in `SearchIndexCoordinatorTests`
("Scheduled file refresh debounces repeated requests") that passes in isolation, passed in an
earlier full run this session, and is documented as pre-existing in bug 027. Nothing here
touches the coordinator.

**Simulator (SC7), against the 742-note real-vault copy:**
1. Typed a capture, swiped right to file it
2. Status line rendered `✓ Filed · inbox/2026-09-01-d1625a5d.md ›` with the chevron
3. Tapped it — log trace confirmed the full chain:
   `CaptureScreen status line tapped` → `RootTabView openFiledNote` → `BrowseScreen opening
   pending note`, all for `2026-09-01-d1625a5d.md`
4. The editor opened on that note showing its captured text
5. Back returned to the Browse root

All success criteria met.

## Residual Risks

- **The independent `ios_visual_evidence_auditor` step was not run.** This session operates
  under a standing instruction not to spawn subagents unless asked, which overrides Step 6 of
  the skill. Verification above is first-party: screenshots plus a log trace of the routing
  chain, not an independent audit.
- **No recording.** The evidence is stills plus logs; the tab-switch transition itself was not
  captured as motion.
- **Dwell time is a judgement call.** 6s was chosen as "long enough to notice and tap" without
  leaving stale chrome on screen. Not validated against real one-handed use.
- **Only exercised on a fresh capture.** The "Already filed" (duplicate) path is unit-tested
  for openability but was not tapped in the simulator.
- **Back goes to the Browse root, not Capture.** Deliberate (see Design decisions), but it is
  a one-way trip out of the capture flow — if that feels wrong in use, the alternative is
  presenting the editor as a sheet over Capture.

## Bugs

_None yet._
