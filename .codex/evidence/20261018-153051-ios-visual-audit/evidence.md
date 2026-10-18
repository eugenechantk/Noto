# iOS Visual Evidence Audit

Verdict: PASS
Timestamp: 2026-10-18 15:30–15:50 HKT
Repository: /Users/eugenechan/dev/personal/Noto (uncommitted changes on main)
Simulator: cc-8701c7e8 — iPhone 17 Pro, iOS 26.3, UDID FA1047D4-3B58-4A9E-983E-8571E43BB15B
App: com.eugenechan.Noto2 (scheme Noto2, Noto.xcodeproj, Debug)

## Change Audited

1. **Library is cache-first** (`.codex/feature/noto2-library-cache.md`). `LibraryModel` + `LibrarySnapshotCache`
   (new, `Packages/NotoVault`) save the last scan to `Library/Caches/NotoLibrary/library-snapshot.plist`; `LibraryHome`
   and `FolderListView` (`Noto2/Browse/BrowseScreen.swift`) read from the model and show a spinner only on first load.
2. **Inbox Stack | List switch** (`bug-reports/045-noto2-inbox-switch-double-capsule.md`). `.sharedBackgroundVisibility(.hidden)`
   on the picker's `ToolbarItem` in `Noto2/Digest/DigestScreen.swift`.

Test vault: seeded with `.maestro/seed-vault.sh` (6 notes, 3 folders) + 8,000 notes in `Bulk/` + 3 notes in `inbox/`.
Timelines are FlowDeck UI-session frames (written on screen change, about every 0.5–1 s). Each `t+` label is measured from the tap.

## Success Criteria

| Criterion | Result | Evidence |
|---|---|---|
| L1 — First Library open after a fresh install (no cache): a spinner shows until the list appears, then the cache file is written | PASS | `03-L1-first-open-spinner.png` + `.screen.json` (`libraryLoading` in tree); `L1-timeline-sheet.png` (spinner t+0.6 s → t+11.3 s, list at t+12.1 s); `04-L1-first-open-loaded.png`; `L1-cache-file.txt` (3,019,252 B, mtime 15:33:59, about 11.6 s after the tap; the cache dir was absent before) |
| L2 — After terminate + relaunch, Library shows the list immediately, no spinner | PASS | `05-L2-app-switcher-before-kill.png`, `06-L2-terminated-home.png` (killed from the app switcher, no process); `07-L2-relaunch-library-instant.png` (taken ≤1.3 s after the tap; tree has no `libraryLoading`); `L2-timeline-sheet.png` (the first frame after the tap, t+0.5 s, is the full list) |
| L3 — A note added on disk while closed is absent from the instant list, then appears at the top of Recent after the silent scan; no spinner at any point | PASS | `08-L3-relaunch-instant-without-new-note.png` (list at once, "Audit Added While Closed" absent); `09-L3-after-silent-scan.png` (note at the top of Recent, "just now"); `L3-timeline-sheet.png` (t+0.6 s list without note → t+11.5 s note at top; no `libraryLoading` in any tree); `L3-timeline.log` (cache rewritten to 3,019,682 B at t+~11 s) |
| L4 — A folder page opens at once (no spinner, no "Nothing here yet." flash), and the count line matches | PASS | `10-L4-bulk-folder-instant.png` ("0 folders · 8000 notes", matching the 8,000 on the Library row and 8,000 files on disk); `L4-timeline-sheet.png` (the first frame after the tap, t+0.8 s, is the full note list; no `libraryLoading`/`browseEmptyState` in any tree); `11-L4-captures-folder-instant.png` (cross-check: "0 folders · 2 notes", matching its row) |
| L5 — Pull to refresh on Library still works and shows only the system refresh control | PASS (see note) | `12-L5-before-pull.png`; `13-L5-pull-refreshing.png` (system refresh control above RECENT, no in-list `libraryLoading` row); `L5-timeline-sheet.png` (control spins t+0.8 s → t+12.9 s, gone at t+13.9 s, which is one full scan; list visible the whole time) |
| I1 — The Stack \| List switch shows a single segmented track, no outer capsule (full-res crop) | PASS | `15-I1-inbox-stack-fullres.png` (1206×2622 frame), `16-I1-titlebar-crop-fullres.png`, `17-I1-switch-zoom-2x.png`, `19-I2-list-titlebar-crop-fullres.png` (List-selected state). Pixel scan: one border on each side at x=750/1145 px (250–382 pt, equal to the picker's 132 pt frame) and one top/bottom edge at y≈183/325 px (47 pt). No second edge outside the track |
| I2 — Tapping List shows the list view; tapping Stack returns to the card stack | PASS | `18-I2-inbox-list.png` + `.screen.json` (3 captures listed under TODAY); `20-I2-back-to-stack.png` (single card, Stack selected); `sim-navigate/…/trace.jsonl` + `final.png` (independent run: List selected with list rows, then Stack with the card) |

## Artifacts

All under `/Users/eugenechan/dev/personal/Noto/.codex/evidence/20261018-153051-ios-visual-audit/`:

- Screenshots `01`–`20` (FlowDeck, 402×874 point resolution) with `.screen.json` accessibility trees where semantic proof matters.
- Full-resolution stills `15`, `16`, `17`, `19`: one frame pulled from `flowdeck ui simulator record` output.
- `L1`–`L5-timeline/` (raw session frames + trees), `L*-timeline-sheet.png` (labelled contact sheets), `L*-timeline.log` (cache file size/mtime polled every 0.5 s).
- `sim-navigate/20261018-154828-in-the-inbox-tab-tap-the-list-segment-of/` (`trace.jsonl`, `final.png`, `replay.sh`).

## Commands

- `flowdeck config get --json` — the saved config is Noto-iOS on another simulator. It was overridden with explicit flags and not modified.
- `flowdeck uninstall com.eugenechan.Noto2 --simulator "FA1047D4-…"` — needed for a true fresh install (see Notes).
- `flowdeck run -s Noto2 -S "FA1047D4-3B58-4A9E-983E-8571E43BB15B" --json` — build succeeded, installed, launched.
- `flowdeck stop <id>`; `.maestro/seed-vault.sh FA1047D4-… --bundle-id com.eugenechan.Noto2`; a Python write of 8,000 `Bulk/` notes and 3 `inbox/` notes.
- `flowdeck ui simulator session start -S "FA1047D4-…" --json` — session 7C23F159, used as the frame source.
- Relaunch without reinstall: tap the "Noto 2" home-screen icon (`flowdeck ui simulator tap "Noto 2"`). Terminate: double `button home` → app switcher → swipe the card up.
- `flowdeck ui simulator tap -p "200,460"` (dismiss keyboard), `tap -p "268,821"` (Library), `tap "libraryFolder_Bulk" --by-id`, `tap -p "349,85"`/`"283,85"` (List/Stack), `swipe --from "201,200" --to "201,620" --duration 1.0` (pull to refresh).
- `flowdeck ui simulator screen -o … --json`; `flowdeck ui simulator record -t 3` (single-frame output, used for the 3x still).
- sim-navigate goal: "In the Inbox tab, tap the List segment of the Stack | List switch in the top right, then tap the Stack segment to return to the card stack". The run completed in 3 steps. Its `--check` scored 0.6 (outcome `checks_failed`), a false negative: the final screenshot and tree show the card stack with Stack selected (value=1). Replay: `sim-navigate/20261018-154828-in-the-inbox-tab-tap-the-list-segment-of/replay.sh`.

## Notes

- **L5 nuance.** I wrote a new note while the app ran, planning to show that only the pull picks it up. The vault `NSFilePresenter` heard the host-side write and ran its own silent refresh (cache rewritten 12 s after the write, before the pull). So the content change does not prove the pull. The pull's own scan is still proven: the system control stayed up for about 12 s, which is one full scan, and nothing else was scanning then. With no work to do, `refresh()` would return at once. The file watcher's silent refresh is extra confirmation of feature-doc flow item 5.
- **The caller's state assumption was wrong.** `flowdeck run` reinstalled into the same data container, and a 2.7 MB `library-snapshot.plist` from an earlier session survived. "Reinstall wipes Caches" did not hold. `flowdeck uninstall` was needed to get a no-cache first open for L1. The same is true for real users: an app update keeps the cache.
- **Frame cadence.** Session frames arrive about every 0.5–1 s, so a spinner shown for less than one frame could in theory be missed. By the code, the spinner and "Nothing here yet." both require `snapshot == nil`, which cannot happen once a snapshot is published.
- **Recording.** `flowdeck ui simulator record` produced a 1-frame (0.067 s) file again. It was used only as a full-resolution still source. Motion proof uses the timed screenshot sequences.
- **Residual risks, not failures:**
  - Every folder open and every Library appearance starts a full vault scan (about 10–12 s of background work at 8k notes). This is unchanged cost, as the feature doc states.
  - `FolderListView.notes` re-filters the whole snapshot (with `standardizedFileURL` per note) about three times per body evaluation. No lag was seen at 8k notes.
  - While the cache read is in flight (`hasCheckedCache == false`), `LibraryHome` renders an empty list, with neither a spinner nor rows. It was not observable here because the cache loads at launch.
  - The folder count line says "8000 notes" while the Library row says "8,000". This formatting predates the change.
- Taps on the Library flows were driven by hand rather than through `sim-navigate`, because the criteria depend on timing measured from the tap. Coordinates were used for tab-bar, keyboard-dismiss and segment taps, from the caller's map and the tree frames.
