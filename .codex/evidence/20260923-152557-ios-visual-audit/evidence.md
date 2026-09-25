# iOS Visual Evidence Audit

Verdict: PARTIAL. All five listed criteria (SC10a to SC10e) pass. The audit also found one new video-layout defect (D1) that none of the five criteria covers.
Timestamp: 2026-09-23 23:26 to 23:42 HKT (UTC dir stamp 20260923-152557)
Repository: /Users/eugenechan/dev/personal/Noto
Simulator: cc-56c91326, CC08DBB1-A2C2-44FE-8D68-CA7381A64EC2 (iPhone 17 Pro, iOS 26.3, 402x874 pt; screenshots are 1 px = 1 pt)
App: com.eugenechan.Noto2 (scheme Noto2), the build that was already installed. It was not rebuilt or reinstalled.

## Change Audited

SC10 of `.codex/feature/noto2-video-tap-to-play.md` says every editor video fills the editor's content width. A portrait video keeps the capped height with black side bars, and the inline player fills the same box. The audit checked two vault notes: "Video scroll audit" (`inbox/2026-09-23-video0002.md`) and "Thais on X" (`inbox/2026-09-23-video0001.md`). Every result below comes from screenshots and the accessibility tree, not from the code.

How the measurements were taken:
- **Box edges** come from the accessibility `Play video` / `Link` frames, cross-checked against pixel scans. A pixel counts as background when it is within ±6 of #0E1116.
- **Text edges** are pixel ink bounds: the top of the ascenders and the bottom of the descenders.
- **Gap** is the distance from the ink edge of the text line to the box edge.

## Success Criteria

| Criterion | Result | Evidence |
|---|---|---|
| SC10a: every video spans the content width, with edges matching the text column and link card | PASS | See the width table below. Landscape, portrait and link card all measure x=21, w=360 (a11y), which is pixels 21 to 380 inclusive. Text ink starts at x=21 on every line. The landscape poster has a 1 px anti-aliased rim at x=20 and x=381; the portrait's black box has partial pixels at 21 and 380. Card and video edges match to the pixel. Files: `01`, `03`, `05`, `30`, `35`, `*-tree.json` |
| SC10b: small, similar gaps above and below each video, with no large empty band | PASS (see notes O1, O2) | Below: landscape **10 pt**, portrait **5 pt**. Above: landscape **29 pt**, portrait **29 pt**. See the gap table below. Files: `30`, `31` to `34` |
| SC10c: "Thais on X" (last line is a portrait video) scrolls far enough to show the whole box, and nothing draws over text | PASS | At maximum scroll the portrait box sits at y 412 to 697 (a11y h=285), fully on screen, with 177 pt of background below it. A second scroll-down did not move the frames (`04` vs `05`), which confirms maximum scroll. No overlay overlaps a text line in any screenshot. Files: `04`, `05`, `*-tree.json` |
| SC10d: tapping the portrait video plays it inline in the same box, and frames advance | PASS | Tapped (201,554) at 23:33:52. The in-video countdown reads 00:29 at t0 (23:33:53) and 00:25 at t1 (23:33:57). The pixel difference between the two frames is confined to the picture area (126..265, 430..670). The player's box edges are unchanged from the poster: x 21 to 380, y 412 to 696. Back then returned to inbox. The landscape video was also checked: it plays inline in its own box (`16`, `17`). Files: `07`, `08`, `09`, `09b`, `10`, `12` |
| SC10e: still correct after closing and reopening "Video scroll audit" | PASS | Reopened after the Thais note played. The frames are identical (landscape 21,278,360x203; portrait 21,563,360x284). Below the navigation bar, the reopened screen is **pixel-identical** to the first open (difference bounding box = None). After scrolling both videos off screen and back, it is again pixel-identical. Files: `13`, `14`, `15`, `*-tree.json` |

### Width measurements (SC10a)

| Element | a11y frame | Pixel columns |
|---|---|---|
| Link card (Thais) | x=21 w=360 | 21 to 380 |
| Landscape video (both notes) | x=21 w=360 h=203 | 21 to 380 (plus a 1 px rim at 20 and 381) |
| Portrait video (both notes) | x=21 w=360 h=284 or 285 | 21 to 380. The picture itself runs 121 to 281, centred. |
| Text lines | n/a | Ink starts at 21 or 22. Wrapped lines end at 380 or less. |

### Gap measurements (SC10b, "Video scroll audit" at scroll offset 0, `01`)

| Gap | Text ink edge | Box edge | Gap |
|---|---|---|---|
| Above landscape | descender bottom at y 248 | top at 278 | 29 pt |
| Below landscape | ascender top at 491 | bottom at 481 | 10 pt |
| Above portrait | descender bottom at 533 | top at 563 | 29 pt |
| Below portrait | ascender top at 852 | bottom at 847 | 5 pt |

For reference, wrapped lines inside one paragraph have an ink gap of about 6 pt, and paragraphs separated by a blank line have about 57 pt. The same measurements in the scrolled view (`02`) were: 30 pt above the portrait, 5 pt below.

## Defect found (outside SC10a to SC10e)

**D1: a video is not drawn while its top edge is in the lower part of the screen, which leaves an empty band where the video should be.**

Steps to reproduce:
1. Open Browse → inbox → "Thais on X".
2. Do not scroll.
3. The landscape video ends at y=742. The portrait video should begin at about y=763 and fill the rest of the screen, but rows 742 to 874 are empty background. The accessibility tree has only one `Play video` element (`03`, `19`).
4. Scroll down 42 pt. The portrait should now start at y=721, but it is still missing, and 700 to 874 is empty (`20`).
5. Scroll down 83 pt. The portrait appears at y=680 (`21`). A side-by-side of steps 4 and 5 is in `22`.

The same thing happens after scrolling back to the top from the bottom (`06`), so it is not only a first-load problem. On a real phone, the bottom 130 to 175 pt of the screen shows nothing until the user scrolls further.

Likely cause (a hypothesis from reading the code, not verified):
- `visibleTextRange()` in `NotoShared/Editor/TextKit2EditorView.swift:5410` finds the range to draw by probing `closestPosition(to:)` at `bounds.maxY + 120`.
- When that probe point lands inside a tall media line, the position it returns is the start of that line. `lineRange(for:)` then stops at the previous line, so the video's block is never passed to `refreshImageOverlayViews`.
- This predicts that any media line taller than 120 pt goes missing while its top is on screen and its bottom is more than 120 pt below the screen. For the portrait video, that means a top edge below about y=709. The observed cut-off falls between 680 (drawn) and 721 (missing), which agrees.
- Images probably have the same bug, since they use the same path. Only the video case was observed.

## Notes

- **O1:** the gap below the video is 10 pt for landscape and 5 pt for portrait. Both are small (well under one 25 pt line pitch) and neither leaves a band, so SC10b passes. The 5 pt difference is still measurable.
- **O2:** the gap above a video (29 pt) is 3 to 6 times the gap below it (5 to 10 pt), so each video sits visibly closer to the text under it than the text over it. This is the same for both orientations and cosmetic only. Video to video in "Thais on X" is 21 pt (`05`: 391 → 412).
- **O3:** once the AVKit inline controls appeared (after tapping the playing video), `flowdeck ui simulator screen` failed with "Failed to parse accessibility tree", and the session stream stopped writing frames. `10` is the last session JPEG: controls fading in, video at its end (00:00). The stream recovered after leaving the note. Playback proof uses `08` and `09`, which were taken before the controls showed.
- **O4:** the simulator was **Shutdown** when the audit started, even though the handoff said the app was running. It was booted with `flowdeck simulator boot` and the app was opened from its home-screen icon. The app was not reinstalled and the vault container was kept.
- **Note files were not modified:** `note-shasums-before.txt` matches `note-shasums-after.txt`.
- **Some synthetic drags did nothing:** drags of 45 pt or less, and slow drags (0.8 to 1.5 s) never scrolled the text view. Probably they fell under the pan threshold or turned into a text-selection press. This is a limit of the test input, not an app bug. Drags that start on a video do scroll the note (`18`).

## Artifacts

All files are under `/Users/eugenechan/dev/personal/Noto/.codex/evidence/20260923-152557-ios-visual-audit/`.

- `01-scroll-audit-open.png` and `-tree.json`: first open, scroll offset 0
- `02-scroll-audit-scrolled.png` and `-tree.json`: portrait gap check after scrolling
- `03-thais-open.png` and `-tree.json`: link card vs video width; D1 visible (no portrait below y=742)
- `04`, `05` (`-thais-scrolled-bottom*`): maximum scroll, whole portrait box visible
- `06-thais-scrolled-back-top.png`: D1 again after scrolling back to the top
- `07-thais-before-tap-portrait.png`, `08-…-t0.png`, `09-…-t1.png`, `09b-…-side-by-side.png`: SC10d
- `10-thais-portrait-inline-controls-session.jpg`: inline controls fading in over the same box
- `12-left-thais-inbox.png`: after leaving the note
- `13-scroll-audit-reopen.png` and `-tree.json`, `14-…-videos-offscreen.png`, `15-…-scrolled-back.png` and `-tree.json`: SC10e
- `16`, `17` (`-scroll-audit-landscape-playing-*`): landscape plays inline in its box
- `18-drag-started-on-video.png` and `-tree.json`: a drag that starts on a video scrolls
- `19-thais-reopen-top.png`, `20-defect-…-offset42-portrait-missing.png`, `21-…-offset83-portrait-drawn.png`, `22-defect-side-by-side-…png`: D1
- `23-final-inbox.png`
- `30-annotated-scroll-audit-edges-gaps-2x.png`: edge lines and gap markers
- `31` to `34` (`-crop-gap-*-4x.png`): zoomed gap crops
- `35-crop-thais-card-vs-video-edges-4x.png`: left and right edge strips of the link card and the video
- `note-shasums-before.txt`, `note-shasums-after.txt`

## Commands

```
flowdeck config get --json                      # saved config is Noto-iOS / iPhone 17, not used; every command passed -S
flowdeck simulator list --json                  # CC08DBB1 was Shutdown
flowdeck simulator boot CC08DBB1-A2C2-44FE-8D68-CA7381A64EC2 --json
flowdeck ui simulator session start -S "CC08DBB1-A2C2-44FE-8D68-CA7381A64EC2" --json
flowdeck ui simulator tap   -S "CC08DBB1-A2C2-44FE-8D68-CA7381A64EC2" -p "x,y"      # coordinates in points (a11y tree has no ids for rows)
flowdeck ui simulator swipe -S "CC08DBB1-A2C2-44FE-8D68-CA7381A64EC2" --from "x,y" --to "x,y" --duration d
flowdeck ui simulator scroll -S "CC08DBB1-A2C2-44FE-8D68-CA7381A64EC2" -d DOWN --distance f [--speed s]
flowdeck ui simulator screen -S "CC08DBB1-A2C2-44FE-8D68-CA7381A64EC2" --output <png>
flowdeck ui simulator screen -S "CC08DBB1-A2C2-44FE-8D68-CA7381A64EC2" --tree --json
flowdeck ui simulator session stop -S "CC08DBB1-A2C2-44FE-8D68-CA7381A64EC2" --json
```

Pixel analysis used Pillow through `uv run --with pillow`; the scripts are in the session scratchpad. Video dimensions came from `ffprobe`: landscape 1280x720 (43.8 s), portrait 720x1280 (30.2 s).
