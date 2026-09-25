# iOS Visual Evidence Audit

Verdict: PASS (with one residual layout note, see Notes)
Timestamp: 2026-09-23 19:41–19:54 HKT
Repository: /Users/eugenechan/dev/personal/Noto
Simulator: cc-56c91326-a36c85ba (iPhone 17 Pro, iOS 26.3), UDID E45291BA-85D3-4EE1-AD0A-3F116DC6636D
App: com.eugenechan.Noto2 (scheme Noto2, Debug, Noto.xcodeproj)

## Change Audited

This is a re-audit of Noto 2 tap-to-play (`.codex/feature/noto2-video-tap-to-play.md`). The previous run, `20260923-192600-ios-visual-audit`, was PARTIAL. The fixes under test are in `Noto2/Digest/DigestMedia.swift` and `DigestScreen.swift`:
- **Tiles:** each tile is a fixed frame (full width, 120 pt tall) with the image drawn as a clipped overlay.
- **Accessibility:** the strip uses `.accessibilityElement(children: .contain)`.
- **Prose:** card text renders inline markdown and keeps line breaks (`DigestCardText.attributed`, `.inlineOnlyPreservingWhitespace`).

The build is fresh. Both source files were modified at 19:38:04. The built `Noto2.debug.dylib` is from 19:43:03 and the `Noto2` binary from 19:43:05.

**Test content.** The auditor wrote these files into the sim vault after running `seed-vault.sh`. Copies are in `seed/`.
- `inbox/2026-09-23-audit0001.md` (front card, 10:30Z) has 5 media lines:
  - a link line
  - `**@thaiscbranco_**`
  - two prose lines, one containing `*two images*`
  - a landscape video (`x-2100…`), a portrait video (`x-2102…`), a square PNG (`coastline.png`), a portrait video (`instagram-…`) and a portrait PNG (`portrait.png`)
- `inbox/…0002.md` (10:20Z) has a link, one prose line with a bold author, and one landscape video.
- `inbox/…0003.md` is plain text.
- `Video Playback Test.md` has prose, a landscape video, and prose. Its shasum is `91fa745494ee8cc50384f0ce0ce6eedbff81143a`.

## Success Criteria

| Criterion | Result | Evidence |
|---|---|---|
| 1a. The 5-media card shows the full prose, with no line hidden | PASS | `01-digest-5-media-card.png`, `02-crop-5-media-card-zoom3x.png`. All 4 prose lines are visible, including "LAST PROSE LINE must stay fully visible." In the tree, the text frame is y 415–491 and the tiles start at y 504, a 13 pt gap. `02b-crop-…-a11y-frames-zoom3x.png` draws the a11y frames: the cyan text box and the red/yellow tile boxes do not intersect. |
| 1b. Exactly 3 equal tiles, 120 pt tall, "+2" on the third | PASS | `01-…-tree.json` has 3 tiles, all 104 wide at x = 36 / 148 / 261, height 119–120 (a11y rounding). `08-…-tree.json` reads 120. "+2" is on the third tile (`02-crop…`). After scrolling the card body 12 pt, the pixels show the image tile spanning y 493–612, which is exactly 120 pt, with rounded corners on all four sides (`04-…-scrolled-12pt.png`, `04b-crop-scrolled-tiles-full-height-zoom3x.png`). |
| 1c. No tile overlaps the text | PASS | Same frames as 1a. Tiles run y 504–623; text ends at 491. |
| 2. `digestVideoThumbnail_<i>` / `digestImageThumbnail_<i>` ids are in the tree with frames | PASS | `01-digest-5-media-card-tree.json`: `digestVideoThumbnail_0` (36,504,104×119, Button, "Play video"), `digestVideoThumbnail_1` (148,504,104×119, Button), `digestImageThumbnail_2` (261,504,104×119, Image, "Image"). The single-video card has `digestVideoThumbnail_0` (36,466,330×120) in `14-…-tree.json`. `tap --by-id` worked on all three ids. |
| 3. `**@author**` renders bold with no asterisks | PASS | `03-crop-bold-author-zoom5x.png`: "@thaiscbranco_" is visibly heavier than the regular line, and `*two images*` is italic. Neither element's a11y label contains `*`. A stroke-weight proxy (bright-pixel ratio) gives 0.162 on the author line vs 0.139 on the regular line. The single-video card also bolds the inline author (`15-crop-single-landscape-video-zoom3x.png`). |
| 4a. Tapping a video thumbnail opens a full-screen player that plays | PASS | Landscape (`digestVideoThumbnail_0`): `05-…t0-194837.jpg`, `06-…t1-194849.jpg` and `07-…t2-194907.jpg` are three different frames (side by side in `06b-…`; mean pixel diff 20.3). Portrait (`digestVideoThumbnail_1`): `09-…`/`10-…` show the portrait clip that matches its thumbnail, with different frames 5 s apart (`10b-…`; mean diff 53.7). |
| 4b. Closing the player returns to the same card | PASS | `08-digest-after-player-close.png` and its tree show the same 6:30 PM card, still "3 to process". It was the same after the portrait player. |
| 4c. Tapping an image opens no player | PASS | `11-digest-tap-image-no-player.png` and its tree: the tree still reads (it can't while the player is up) and the card is unchanged. |
| 4d. A left swipe that starts on a thumbnail snoozes the card | PASS | `12-digest-before-swipe.png` says "3 to process". The swipe went from (300,550), on `digestImageThumbnail_2`, to (20,555). `13-digest-snoozed-toast.jpg` shows "Snoozed until Sep 30, 2026". `14-digest-after-snooze.png` and its tree say "2 to process" with the next card showing. On disk, `13b-snoozed-capture-on-disk.md` has `snoozed_until: 2026-09-30T11:52:04Z`. |
| 4e. A single landscape video with one text line renders correctly | PASS | `14-digest-after-snooze.png`, `15-crop-single-landscape-video-zoom3x.png`: the text (y 415–453, wraps to 2 lines) is fully visible, and the 330×120 tile at y 466–586 sits below it with rounded corners and no overlap. |
| 5. Editor: tapping a video line opens the player (SC2) | PASS | `16-editor-note-with-video.png` and its tree show `editor_video_157` (Button, "Play video", 360×203). `17-editor-player-presenting.jpg` catches the cover sliding up. `18-…t1-195323.jpg` and `19-…t2-195342.jpg` are different frames (`19b-…`). After closing, `20-editor-after-player-close.png` shows the same note. The shasum after close, `91fa7454…`, matches the seed (`note-shasum-after-close.txt` vs `seed-shasums.txt`). |

## Artifacts

All paths are relative to `/Users/eugenechan/dev/personal/Noto/.codex/evidence/20260923-194126-ios-visual-audit/`:
- **Layout, ids, bold:** `01-digest-5-media-card.png` and `-tree.json`, `02-crop-5-media-card-zoom3x.png`, `02b-crop-5-media-card-a11y-frames-zoom3x.png`, `03-crop-bold-author-zoom5x.png`, `04-digest-card-body-scrolled-12pt.png` and `-tree.json`, `04b-crop-scrolled-tiles-full-height-zoom3x.png`.
- **Digest player:** `05-…`, `06-…`, `06b-…`, `07-…` (landscape); `09-…`, `10-…`, `10b-…` (portrait); `08-digest-after-player-close.png` and `-tree.json`; `11-digest-tap-image-no-player.png` and `-tree.json`.
- **Swipe and single video:** `12-digest-before-swipe.png`, `13-digest-snoozed-toast.jpg`, `13b-snoozed-capture-on-disk.md`, `14-digest-after-snooze.png` and `-tree.json`, `15-crop-single-landscape-video-zoom3x.png`.
- **Editor:** `16-editor-note-with-video.png` and `-tree.json`, `17-editor-player-presenting.jpg`, `18-…`, `19-…`, `19b-editor-player-side-by-side.jpg`, `20-editor-after-player-close.png` and `-tree.json`, `note-shasum-after-close.txt`.
- **Test inputs:** `seed/*.md`, `seed-shasums.txt`.

## Commands

- `flowdeck config get --json`. The saved config is Noto-iOS on the shared iPhone 17, so the guard's session sim was used instead.
- `flowdeck run -s Noto2 -S "E45291BA-85D3-4EE1-AD0A-3F116DC6636D" --json`: build succeeded, app pid 22777.
- `.maestro/seed-vault.sh E45291BA-85D3-4EE1-AD0A-3F116DC6636D --bundle-id com.eugenechan.Noto2`. The script printed the container path; the auditor did not call simctl.
- `flowdeck ui simulator open-url "noto2://capture" -S "…"`, then `flowdeck ui simulator tap "Open" -S "…"`
- `flowdeck ui simulator session start|stop -S "…" --json`. Sessions E8F72546 and D13BF424; the first was restarted after its ring stalled on the player.
- `flowdeck ui simulator hide-keyboard`, then `tap -p "160,805"` (Digest) and `tap -p "328,805"` (Browse)
- `flowdeck ui simulator tap "digestVideoThumbnail_0|digestVideoThumbnail_1|digestImageThumbnail_2|editor_video_157" --by-id -S "…"`
- `flowdeck ui simulator tap -p "201,650"` then `tap -p "43,80"`: reveal the player controls, then tap the close ✕
- `flowdeck ui simulator swipe --from "200,560" --to "200,500" --duration 2.0` (scroll the card body) and `--from "300,550" --to "20,555" --duration 0.35` (snooze)
- `flowdeck ui simulator screen -o <file>.png -S "…" --json` for screenshots and trees

## Notes

- **Residual layout issue (not a regression; the caller should decide):** on this sim the Digest card body is a fixed-height `ScrollView` whose visible area is about 313 pt (y 299–612). The front capture is 325 pt tall: link card 104 + 12 + 4 prose lines 76 + 13 + strip 120. It overflows by about 12 pt.
  - **At rest:** the bottom 11 pt of the strip sits below the card's scroll edge. The tiles show 109 pt, with square bottom edges (pixel scan: tile y 504–612, clip at 613). `02b-…` shows the a11y frames running past the clip.
  - **Scrolling reveals it:** scrolling the body 12 pt shows the full 120 pt tiles (`04b-…`).
  - **Why it matters:** this is the scroll container doing its job, not the old overlap bug. The text is never covered. But a typical Hermes post (link, author, three or more lines, media) will hit this on iPhone 17 Pro, and there is no scroll affordance at rest, so the strip looks cut off.
  - **Possible fixes:** pin the strip outside the `ScrollView` below the prose, or cap prose lines when media is present. I made no code change.
- **Scrolling quirk:** a 38 pt / 1.5 s synthetic drag inside the card did not scroll the body. A 60 pt / 2 s drag did. This is likely the card's simultaneous `DragGesture` competing with the scroll view. It is a synthetic-input observation only and has not been checked with a real finger.
- **Tooling:**
  - While `AVPlayerViewController` shows its controls or end card, the a11y tree fails to parse ("Failed to parse accessibility tree") and the session ring stops writing frames. Player frames are copies of the session's `latest.jpg`, taken while the controls were hidden. For that reason there are no player-control screenshots with a time label; playback is shown by the frames changing over 12–20 s instead.
  - The ring (500 ms) missed the mid-flight Snooze overlay. The toast, the count drop and the on-disk `snoozed_until` prove the snooze.
- **Not re-run:** unit tests (the caller reports Noto2Tests 103/103). SC5 (a dataless iCloud video) cannot be tested in the simulator because the container vault is local. No iPad run; the caller asked for iPhone only.
- The screenshots are 402×874, so the sim renders at 1× points. Crops are upscaled 3–5× for legibility.
