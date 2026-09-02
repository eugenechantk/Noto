# iOS Visual Evidence Audit

Verdict: PASS (all 8 caller criteria) — with 2 defects found outside the criteria list

Timestamp: 2026-09-01 21:10–21:20 (+0800)
Repository: /Users/eugenechan/dev/personal/Noto
Simulator: cc-ce4e8f92-aa4d4913 — iPhone 17, iOS 26.3 — UDID `6A3AB13E-6A15-46C7-97BC-531A2602EE84`
App: com.eugenechan.Noto2 (scheme `Noto2`, workspace `Noto.xcodeproj`, Debug)

> Note on simulator: the caller specified `114ACF68-B1DD-4946-8786-5106F4AA581A`, but this session's
> `flowdeck-guard.sh` hook created and enforced its own simulator and BLOCKS any other UDID. All work
> was done on `6A3AB13E-6A15-46C7-97BC-531A2602EE84`.

## Change Audited

A fourth "Digest" tab (`tray.full`) in Noto 2 that reads the vault's `inbox/` folder and presents due
captures one at a time on a swipeable card, oldest first. Four outcomes per capture: swipe-left snooze
(+7 days), Add to an existing note, Create a new note, Discard (confirmed).

Fixtures written by the auditor into the seeded vault's `inbox/`:

| File | `created` | Note |
|---|---|---|
| `2026-08-15-aaaa1111.md` | 2026-08-15T09:00:00Z | has `snoozed_until: 2026-12-01T12:00:00Z` (future) — must be hidden and uncounted. Deliberately the *oldest* file, so an unfiltered oldest-first queue would surface it first. |
| `2026-08-20-bbbb2222.md` | 2026-08-20T10:15:00Z | due — expected first card |
| `2026-08-25-cccc3333.md` | 2026-08-25T14:30:00Z | due |
| `2026-08-30-dddd4444.md` | 2026-08-30T08:45:00Z | due |
| `2026-08-31-eeee5555.md` | 2026-08-31T11:00:00Z | added later, for the discard test |

## Success Criteria

| # | Criterion | Result | Evidence |
|---|---|---|---|
| 1 | Digest tab exists in the tab bar; card stack + "N to process" line | **PASS** | `01-digest-launch.png` — 4th tab `Digest` selected, card visible, `digestRemainingCount` = "3 to process". `01-digest-launch-tree.json` confirms ids `digestRemainingCount`, `digestCardDate`, `digestCard`, `digestBackCard`, `digestAddToButton`, `digestCreateButton`, `digestDiscardButton`. See Note 1 on the "stack". |
| 2 | Future-`snoozed_until` captures are neither counted nor shown | **PASS** | 4 files on disk, count reads **3**, and the first card is `OLDEST capture` (Aug 20) not `SNOOZED CAPTURE` (Aug 15) — `01-digest-launch.png`. Re-confirmed on a cold relaunch later: 3 inbox files, 2 snoozed, count = "1 to process" and only `DISCARD ME` shown (`15b-discard-flow-frames.png`). |
| 3 | Oldest-first by frontmatter `created` | **PASS** | Aug 20 → (snooze) → Aug 25 → (create) → Aug 30. `01-digest-launch.png` (Aug 20), `03-after-snooze.png` (Aug 25), `11-after-create.png` / tree (Aug 30). |
| 4 | Swipe LEFT: card flies off left, count drops, file gains `snoozed_until` ≈ +7 days, body and other keys unchanged | **PASS** | Recording `02-swipe-left-snooze.mov`; frames `02b-swipe-left-snooze-frames.png` show the amber "Snoozed" overlay card rotating off the LEFT edge, the back card rising, and the next capture landing. Count 3 → **2** (`04-count-after-snooze.png` / `-tree.json`). On disk: unified diff before/after is exactly one added line, `+snoozed_until: 2026-09-08T13:11:39Z`, against an action wall-clock of `2026-09-01T13:11:39Z` — exactly +7 days. `inbox-before-snooze.txt` vs `vault-final-state.txt`. |
| 5 | "Create" sheet: ✕ leading, filled-orange ✓ trailing, capture preview, Add to/Create segmented control, pre-filled Title with ✕ clear, Folder picker with **no `inbox`**; confirming writes `<folder>/<Title>.md` with frontmatter + `# <Title>` + body and deletes the inbox file | **PASS** | `07-create-sheet.png` shows every element; `07-create-sheet-tree.json` confirms `digestFileCloseButton`(*), `digestCreateConfirmButton`(*), `digestFileCapturePreview`, `digestFileModePicker`, `digestCreateTitleField` (pre-filled from the capture), `digestCreateTitleClearButton`, `digestCreateFolderPicker`. Folder list = **Vault root, Archive, Captures, Projects — `inbox` absent** (`08-folder-picker.png`, `08-folder-picker-tree.json`). Clear button works and disables ✓ (`09-title-cleared.png`), retyped title (`10-create-ready.png`). Fly-off right + "Created Q4 Roadmap One Pager" outcome: `06-create-flow.mov`, `06b-create-flyoff-frames.png`. On disk `artifact-created-note.md`: `---\nid:…\ncreated:…\nupdated:…\n---\n# Q4 Roadmap One Pager\n\nMIDDLE capture: draft the Q4 roadmap one-pager.\n` at `Projects/Q4 Roadmap One Pager.md`, and `inbox/2026-08-25-cccc3333.md` is gone. |
| 6 | "Add to" opens a searchable note picker with **no `inbox/` notes**; choosing one appends the capture after exactly one blank line, leaves the rest untouched, deletes the inbox file | **PASS** (with a caveat, see Defect B) | `12-addto-picker.png` + `12-addto-picker-tree.json`: 7 rows, all non-inbox, `.searchable` bar present. Two inbox files existed at that moment and neither appeared. Searching `Capture` — a word in every inbox capture's first line, and therefore in its derived title — yields `No notes match "Capture"` (`13-addto-search-no-inbox.png`, `13-addto-search-tree.json`), so the exclusion holds under search too, not just the empty-query list. On disk, `artifact-target-note-before.md` vs `artifact-target-note-after.md`: the only change is `…next Thursday.\n` → `…next Thursday.\n\nNEWEST capture: buy tickets for the November trip.\n` — one blank line, nothing else altered — and `inbox/2026-08-30-dddd4444.md` deleted. |
| 7 | Trash button asks "Discard this capture?" before deleting | **PASS** | `05-discard-confirmation.png` + `05-discard-confirmation-tree.json`: dialog titled exactly "Discard this capture?" with "The note is deleted from your vault. This can't be undone." and a destructive **Discard**. Dismissing it left all 4 inbox files intact. Full confirm→delete path recorded in `15-discard-flow.mov` / `15b-discard-flow-frames.png`; afterwards only the 2 snoozed files remain and the total `.md` count is unchanged apart from that one deletion (`vault-final-state.txt`). |
| 8 | "Inbox clear" empty state after the last due capture | **PASS** | `14-after-addto.png` and `17-after-discard.png` — tray glyph, "Inbox clear", "Everything you captured has been filed or snoozed.", `digestEmptyState`. |

(*) The two toolbar circle buttons are not exposed in the accessibility tree and had to be tapped by
point (✕ ≈ 42,100; ✓ ≈ 359,100), as the implementation notes warned. They are visually correct in
`07-create-sheet.png`: circular ✕ leading, filled-orange circular ✓ trailing.

## Defects found (outside the 8 criteria, but real)

**A. The Digest never reloads after its first load — new captures don't appear.** `DigestScreen`
loads once (`.task { if !model.hasLoaded { await model.load() } }`) and its `.refreshable` is attached
to a `GeometryReader`/`VStack` with no scroll view, so pull-to-refresh is inert. With the empty state
on screen I wrote a new due capture to `inbox/`, pulled down, and switched to Capture and back — the
Digest still read "Inbox clear" while a due capture sat on disk (`16-digest-after-tab-return.png` +
`inbox-listing-while-empty-state-shown.txt`). Only an app relaunch surfaced it. This is the app's own
primary loop: Capture writes to `inbox/`, Digest reads it. Today a user who captures a thought and
taps over to Digest is told the inbox is clear. `RootTabView` has no digest reload on `scenePhase`
or `NoteSyncCenter` either.

**B. Add-to does not refresh the target note's timestamp for notes written by the main Noto app.**
Feature-doc SC3 requires "refreshes the target's `modified:` stamp". `DigestFiling.append` calls
`VaultMarkdown.updateTimestamp`, which only rewrites a line beginning `updated:`. Noto 2 writes
`updated:`; the main Noto app and the seeded vault write `modified:` (as documented in CLAUDE.md's
frontmatter contract). Verified live: `Meeting Notes.md` still reads `modified: 2026-03-15T09:00:00Z`
after the append (`artifact-target-note-after.md`). Same root cause makes the note Digest *creates*
carry `updated:` rather than the vault's `modified:` (`artifact-created-note.md`), so the same vault
now holds two timestamp conventions. Under the caller's criterion 6 wording ("leaves the rest of the
note untouched") this is a pass; under the feature doc's SC3 it is a fail. Flagging it as the latter.

## Notes and smaller observations

1. **"Card stack" is only a stack while dragging.** `digestBackCard` is present in the hierarchy but
   its opacity is driven by drag progress, so at rest a single card is visible (`01-digest-launch.png`).
   The back card does rise correctly mid-swipe (`02b-swipe-left-snooze-frames.png`). Reads as
   intentional; noting it because "card stack" in the criterion implies a visible stack.
2. **Suggested title produces an awkward filename.** The Create form seeds the title from the whole
   first line, so the default filename was
   `MIDDLE capture： draft the Q4 roadmap one-pager..md` — a fullwidth colon from filename
   sanitisation and a doubled dot from the sentence's own full stop (`07-create-sheet.png`). Legal,
   but it is the default a user taps through.
3. **The discard confirmation renders as a popover anchored above the trash button and overlaps the
   tab bar**, with the destructive "Discard" button sitting directly on top of the Digest tab item
   (`05-discard-confirmation.png`). There is no visible "Keep" — SwiftUI drops the cancel button in
   popover presentation and relies on tap-outside. That matches system behaviour, but the destructive
   action landing on a tab target is worth a look.
4. **Picker header order.** In "Add to" the search field sits *above* the capture preview and the
   Add to/Create segmented control (`12-addto-picker.png`), so the mode switch is below the search
   box it does not apply to.

## Not verified

- `Title(2).md` filename-collision resolution (feature-doc SC4) — not in the caller's criteria list;
  covered by package tests, not exercised in the UI.
- Write-failure rollback (SC6) and the dataless-iCloud "Downloading from iCloud…" card state — cannot
  be induced on a simulator vault without editing code.
- Swipe **right** to open the file sheet — the buttons were used instead; only swipe-left was
  exercised as a gesture.
- iPad / macOS: Noto 2 is iOS-only; audited on iPhone 17 only.

## Artifacts

All paths relative to `/Users/eugenechan/dev/personal/Noto/.codex/evidence/20260901-211025-ios-visual-audit/`.

| File | What it proves |
|---|---|
| `01-digest-launch.png`, `01-digest-launch-tree.json` | Criteria 1, 2, 3 |
| `02-swipe-left-snooze.mov`, `02b-swipe-left-snooze-frames.png` | Criterion 4 animation |
| `03-after-snooze.png`, `04-count-after-snooze.png`, `04-count-after-snooze-tree.json` | Criterion 4 outcome line + count 3→2 |
| `05-discard-confirmation.png`, `05-discard-confirmation-tree.json` | Criterion 7 |
| `06-create-flow.mov`, `06b-create-flyoff-frames.png` | Criterion 5 flow + fly-off |
| `07-create-sheet.png`, `07-create-sheet-tree.json` | Criterion 5 sheet chrome |
| `08-folder-picker.png`, `08-folder-picker-tree.json` | Criterion 5 folder list excludes `inbox` |
| `09-title-cleared.png`, `10-create-ready.png`, `11-after-create.png` | Criterion 5 title clear + confirm |
| `12-addto-picker.png`, `12-addto-picker-tree.json`, `13-addto-search-no-inbox.png`, `13-addto-search-tree.json` | Criterion 6 picker excludes `inbox/` |
| `14-after-addto.png`, `17-after-discard.png` | Criterion 8 |
| `15-discard-flow.mov`, `15b-discard-flow-frames.png` | Criterion 7 confirm→delete |
| `16-digest-after-tab-return.png`, `inbox-listing-while-empty-state-shown.txt` | Defect A |
| `artifact-created-note.md` | Criterion 5 on-disk output |
| `artifact-target-note-before.md`, `artifact-target-note-after.md` | Criterion 6 on-disk output + Defect B |
| `inbox-before-snooze.txt`, `vault-final-state.txt` | Criterion 4 byte-level diff, final vault |

## Commands

```
flowdeck config get --json
flowdeck run -s Noto2 -S "6A3AB13E-6A15-46C7-97BC-531A2602EE84" --json
.maestro/seed-vault.sh 6A3AB13E-6A15-46C7-97BC-531A2602EE84 --bundle-id com.eugenechan.Noto2 --initial-tab digest
flowdeck run --no-build -s Noto2 -S "6A3AB13E-..." --json          # relaunch after seeding (data container survived)
flowdeck ui simulator session start -S "6A3AB13E-..." --json
flowdeck ui simulator screen -S "6A3AB13E-..." -o <file>.png
flowdeck ui simulator screen -S "6A3AB13E-..." --tree --json
flowdeck ui simulator record  -S "6A3AB13E-..." -o <file>.mov -t <secs> --force
flowdeck ui simulator swipe   -S "6A3AB13E-..." --from "330,440" --to "40,450" --duration 0.25
flowdeck ui simulator tap     -S "6A3AB13E-..." --by-id digestCreateButton | -p "x,y"
flowdeck ui simulator type    -S "6A3AB13E-..." "Q4 Roadmap One Pager"
flowdeck ui simulator hide-keyboard -S "6A3AB13E-..."
```

`xcrun simctl get_app_container` was used only to locate the data container for reading/writing vault
fixtures (the container UUID changes across a `flowdeck run`); no build, launch or simulator control
was done outside FlowDeck. `ffmpeg`/`ffprobe` were used only to turn the FlowDeck `.mov` recordings
into contact sheets.

## Limitations

- Coordinate taps were needed for the sheet toolbar ✕/✓, the folder-picker rows, the search clear
  button and the tab bar, because those elements either carry no identifier or were occluded by the
  Capture tab's keyboard accessory.
- Only three due captures were exercised; no long/scrolling capture body was tested, so the in-card
  `ScrollView` (`digestCardBody`) is unproven.
- All timestamps are simulator local time (UTC+8); the `created` fixtures are UTC, hence the
  "Aug 20, 2026 at 6:15 PM" rendering of `2026-08-20T10:15:00Z`.
