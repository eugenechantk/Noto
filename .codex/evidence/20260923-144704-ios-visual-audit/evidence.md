# iOS Visual Evidence Audit

Verdict: PARTIAL
Timestamp: 2026-09-23 22:47–23:09 HKT (14:47–15:09 UTC)
Repository: /Users/eugenechan/dev/personal/Noto
Simulator: cc-56c91326, iPhone 17 Pro, iOS 26.3, UDID CC08DBB1-A2C2-44FE-8D68-CA7381A64EC2 (402×874 pt)
App: com.eugenechan.Noto2 (scheme Noto2), the build already installed. Not rebuilt or reinstalled.

## Change Audited

Noto 2 editor inline video playback (`.codex/feature/noto2-video-tap-to-play.md`, SC7–SC10), plus the SC3 regression check.
- Tapping a video thumbnail plays it inline in an embedded `AVPlayerViewController`.
- The native full-screen round trip works.
- Only one video plays at a time; it stops when scrolled off screen or when you leave the note.
- Videos are full content width.

Test notes (from the simulator vault, unchanged by this audit; `seed-shasums.txt` = `final-shasums.txt`):
- `inbox/2026-09-23-video0001.md` "Thais on X": a link card, a landscape X video (1280×720, 43.9 s), then a portrait Instagram video (720×1280, 30.4 s) on the last line.
- `inbox/2026-09-23-video0002.md` "Video scroll audit": a text line above each video, a text line below each video, and 40 padding paragraphs.

## Success Criteria

| Criterion | Result | Evidence |
|---|---|---|
| **SC7**: tapping a thumbnail plays it inline at the thumbnail's position and size, not full screen | PASS | `08`/`09`: the a11y tree adds a `Video` element at exactly the thumbnail frame (21,539,360×203). Pixel edges are x 21–380, y 539–741/742 while playing, the same as the thumbnail in `07`. The nav bar and text stay on screen. |
| SC7: native iOS inline controls | PASS | `11-sc7-inline-native-controls.jpg` shows full-screen, AirPlay, mute, −10/+10, pause, a scrubber with 0:18 / −0:26, and speed. The log shows `AVMobileGlassControlsViewController` created (native AVKit). |
| SC7: frames advance between two screenshots | PASS | `08` → `09` (3 s apart): mean pixel difference inside the video box is 84.8; the text area difference is 0.0. First run: `04` → `05`. |
| SC7: stays on its line when the note scrolls | PASS | `10`: after a 351 pt scroll the `Video` element and the thumbnail are both at y 188 (pixel run 187–390), still playing. `33`: in the second note it moved 278 → 88 with its line. |
| **SC8**: the full-screen button opens native full screen on the same playback, and it keeps playing | PASS | `17` inline at 0:03 → `12`/`13` native full screen with frames advancing → `18` full-screen controls at 0:09, 5 s later. The log (`log-excerpts.txt` §A) shows the player `Playing` without interruption from 22:59:25.035 through `enterFullScreen:` at 22:59:31.914, with no state change. Run 1: full screen reached 0:25 after 25–28 s (`14`). |
| SC8: closing full screen returns the video to its line | PASS | `21`: after ✕, the `Video` element is back at (21,539,360×203) on its line. Also `16` (run 1). |
| SC8: no AVKit "was deallocated while its contents were being presented full screen" | PASS | 0 occurrences in all Noto2 logs from 22:49 to 23:09 (13,456 lines), including 2 full-screen round trips. |
| **SC9**: tapping the second video stops the first (thumbnail and badge come back) and plays the second inline | PASS | `25b-sc9-sequence-side-by-side.png` (`22`→`23`→`24`→`25`): the landscape shows its poster with the play badge again; the portrait plays (00:28 → 00:25). Log §B: landscape `Paused` at 23:01:29.297, its AVPlayerViewController deallocated at .309, then the portrait `Playing` at .344. |
| SC9: scrolling a playing video completely off screen stops it | PASS | `35b` (`32`→`33`→`34`→`35`): it keeps playing while partly visible (`33`) and stops once fully off screen. Log §C: `Paused` at 23:06:14.578, controller and AVPlayer deallocated, 0 audio buffers afterwards. Scrolling back shows the thumbnail with its badge (`35`). |
| SC9: leaving the note (back button) stops playback | PASS | `26`: inbox list. Log §B: while the portrait played, 66 audio buffers were queued between 23:01:30 and 23:01:43. After back at 23:01:43.25: `Paused` at 43.775, controller deallocated at 43.776, 0 buffers afterwards. |
| **SC10**: both videos fill the content width (edges line up with the text column and link card) | PASS | Pixel measurements (1 px = 1 pt): link card x 21–380 (`01`); landscape x 21–380; portrait x 21–380 (`02`, `27`); text column starts at x 22. |
| SC10: portrait inline player fills the same box | PASS | Thumbnail box x 21–380, y 413–695 (`22`). Playing box x 21–380, y 413–695 (`24`, `25`). Same a11y frame (21,412,360×285). |
| SC10: portrait does not overlap the text above or below, and does not run past the end of the note | PASS on overlap and note end; **defect D1** | No overlap: in `27` the text above ends at y 248, the landscape box is 278–480, the text below is 492–532, and the portrait starts at 562. In the Thais note the portrait (last line) ends at y 696–711 and the scroll stops there (`03`, `31`). **But** when text follows the portrait, a **~379 pt blank gap** sits between the portrait box and the next line (`30`: box ends at y 392, next text at y 771). Compare 12 pt below the landscape. See D1. |
| **SC3** (regression): long-pressing a non-playing thumbnail puts the caret on that line, with no player | PASS | `36` → `37`: a 1.0 s press on the landscape thumbnail brings up the keyboard and editor toolbar with the caret on the video line (orange caret at x 21 from y 121). The a11y tree has no `Video` element; the log has no `initWithNibName`/`Playing` after the press. The note file is unchanged. |

## Defects

**D1: blank gap of about 379 pt below a portrait video when text follows it (SC10 layout)**

- Repro:
  1. Browse → inbox → "Video scroll audit".
  2. Scroll until the portrait Instagram video is near the top.
  3. The next line ("Text line directly below the portrait video.") starts about 379 pt below the video box. Below the landscape video the gap is 12 pt.
  - It persists after the note is closed and reopened (`29`, `34`, `30`).
- Measured: portrait box 284 pt (y 108–392), next glyph top at y 771 (`30-sc10-portrait-gap-below.png`, `30b-sc10-side-by-side.png`).
- Cause (arithmetic matches the measurement): `ImageLayoutFragment.layoutFragmentFrame` uses `ImageFragmentGeometry.aspectAdjustedFragmentHeight`, which has no cap.
  - For a 720×1280 video at 360 pt that gives 640 + 2×8 = 656 pt.
  - `overlaySize` caps the drawn box at 300 − 2×8 = 284 pt.
  - The line therefore reserves 656 pt but draws 284 pt, leaving about 364 pt + 12 pt paragraph spacing empty.
  - Files: `NotoShared/Editor/TextKit2EditorView.swift`, `aspectAdjustedFragmentHeight` (~line 1721) and `overlaySize` (~line 1705).
- This contradicts the feature doc's SC10 premise ("the capped height (the line TextKit reserves)").
- It is invisible in "Thais on X" only because the portrait is the last line there.
- It likely affects portrait images too (same fragment path). Not verified: there is no portrait image in the vault.

## Observations (not criterion failures)

- **O1: After ✕ in full screen, the inline player comes back paused.**
  - Log §A (untruncated line in §F): `exitFullscreen:` at 22:59:38.330, then `Paused … change reason: ClientInitiated` at 22:59:38.819, right after the transition completes.
  - The controller stays embedded (the `Video` element is still at the line in `21`), so this is not the app's `stop()`. It matches AVKit's Done/✕ behaviour.
  - `19`/`20` are identical 5 s apart.
  - SC8 only requires the video to return to its line. If "keeps playing after close" is wanted, resume in the `willEndFullScreenPresentation` coordinator completion.
- **O2: The long-press caret is 300 pt tall** (x 21, y 121–420 in `37`, crop `37b`). It runs past the 203 pt landscape box, over the text line below, because the caret uses the paragraph's `minimumLineHeight` 300, not the 218.5 pt fragment. Cosmetic, and probably pre-existing.
- **O3: Touches from an unknown source hit this simulator** at 22:52:43–22:52:45, while the auditor was idle.
  - They started the portrait video, paused it, played it and paused it again (`06-unexplained-touches-portrait-started-and-paused.jpg`, log §D).
  - No process in `ps` targeted the UDID apart from this audit's FlowDeck session, which was then stopped.
  - It did not happen again in the remaining ~15 minutes.
  - All criterion evidence comes from later runs in which every touch in the log matches an auditor action.

## Artifacts

Evidence directory: `/Users/eugenechan/dev/personal/Noto/.codex/evidence/20260923-144704-ios-visual-audit/`

- FlowDeck PNGs (402×874, 1 px = 1 pt) plus `-tree.json` a11y snapshots: `01`–`05`, `07`–`10`, `16`, `21`–`38`.
- xcodebuildmcp JPEGs (368×800, ×0.915; used while AVKit controls were on screen, because FlowDeck screen then fails with "Failed to parse accessibility tree"): `06`, `11`–`15`, `17`–`20`.
- Composites: `11b-sc7-side-by-side.png`, `21b-sc8-side-by-side.png`, `25b-sc9-sequence-side-by-side.png`, `35b-sc9-scroll-off-sequence.png`, `30b-sc10-side-by-side.png`, `37b-crop-caret-zoom3x.png`.
- Logs: `log-excerpts.txt` (§A full screen, §B switch and back, §C scroll off, §D unexplained touches, §E whole-session counts, §F full pause-reason line), `log-player-lifecycle.txt`.
- Vault integrity: `seed/` (note copies), `seed-shasums.txt`, `final-shasums.txt` (identical).

## Commands

- `flowdeck config get --json` (saved config targets Noto-iOS / another simulator; not used, so every command passed `-S`)
- `flowdeck simulator boot "CC08DBB1-A2C2-44FE-8D68-CA7381A64EC2"` (the simulator was shut down when the audit started)
- The app was launched by tapping the "Noto 2" home-screen icon: `flowdeck ui simulator tap "Noto 2" -S …`. No `flowdeck run` was used, so the container was kept.
- `flowdeck ui simulator screen -S "CC08DBB1-…" --output <png> --json`
- `flowdeck ui simulator tap <id> --by-id` / `tap -p "x,y"` / `tap -p … --duration 1.0` (long-press) / `swipe --from … --to … --duration …`, all with `-S "CC08DBB1-A2C2-44FE-8D68-CA7381A64EC2"`
- `flowdeck ui simulator session start|stop -S …`: the session stopped writing frames while AVKit was on screen.
- `xcodebuildmcp ui-automation screenshot --simulator-id CC08DBB1-A2C2-44FE-8D68-CA7381A64EC2` (fallback stills)
- `xcrun simctl spawn CC08DBB1-… log show --style compact --predicate 'process == "Noto2"'`
- `xcrun simctl get_app_container CC08DBB1-… com.eugenechan.Noto2 data` + `shasum` (vault integrity)

## Notes

- Coordinates: taps used a11y identifiers where they exist (`editor_video_306/352/201`, `hide_keyboard_button`). Point coordinates were used for Back (38,84), note rows, the reveal-controls tap, AVKit's full-screen button (49, top+25) and ✕ (43,84); AVKit exposes no identifiers.
- Timing: AVKit inline controls auto-hide after about 3 s. The first full-screen attempt (22:56:52) landed on hidden controls and only revealed them. Reliable runs tapped reveal and then the control back to back.
- Environment:
  - The simulator was **shut down** at the start, not "running". It was booted, and Noto 2 was launched from its icon.
  - One flowdeck `--help` call without `-S` made the session hook create and boot `cc-56c91326-a114c46f` (C80FE54E-90BA-4A7E-9985-827DF7228F2B). The audit shut it down but did not delete it.
- Audio: the simulator reports system mute YES (the AVKit mute glyph shows). Playback was judged from frames and `Playing`/`Paused` log states, not audibility. No `RebuildIOContext`/`StartIO` events occurred, so no audio-device glitch confounded the results.
- Not covered: picture in picture, editing text while a video plays, iPad.
